import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public protocol CodexUsageReading: Sendable {
  func fetchUsage() async throws -> CodexUsageObservation
}

public protocol CodexAppServerRunning: Sendable {
  func readRateLimits(executable: URL, timeout: TimeInterval) async throws -> Data
}

public enum CodexUsageError: LocalizedError, Equatable, Sendable {
  case executableNotFound
  case timedOut
  case commandFailed
  case invalidResponse
  case unavailable

  public var errorDescription: String? {
    switch self {
    case .executableNotFound:
      "Codex CLI was not found."
    case .timedOut:
      "Codex usage did not respond in time."
    case .commandFailed:
      "Codex usage could not be read."
    case .invalidResponse:
      "Codex returned an unsupported usage response."
    case .unavailable:
      "Codex usage is unavailable for the current authentication mode."
    }
  }
}

public enum CodexExecutableLocator {
  public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment)
    throws -> URL
  {
    let fileManager = FileManager.default
    var candidates: [String] = []

    if let explicit = environment["MOMENT_MONITOR_CODEX_PATH"], !explicit.isEmpty {
      candidates.append(explicit)
    }

    candidates.append(contentsOf: [
      "/Applications/ChatGPT.app/Contents/Resources/codex",
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
      "/usr/bin/codex",
      "/opt/local/bin/codex",
    ])

    if let path = environment["PATH"] {
      candidates.append(
        contentsOf:
          path
          .split(separator: ":")
          .map { String($0) + "/codex" })
    }

    for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
      return URL(fileURLWithPath: candidate)
    }

    throw CodexUsageError.executableNotFound
  }
}

public struct CodexUsageClient: CodexUsageReading, Sendable {
  private let executable: URL
  private let runner: any CodexAppServerRunning
  private let timeout: TimeInterval
  private let now: @Sendable () -> Date

  public init(
    executable: URL,
    runner: any CodexAppServerRunning = ProcessCodexAppServerRunner(),
    timeout: TimeInterval = 10,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.executable = executable
    self.runner = runner
    self.timeout = timeout
    self.now = now
  }

  public static func live(timeout: TimeInterval = 10) throws -> Self {
    try Self(executable: CodexExecutableLocator.locate(), timeout: timeout)
  }

  public func fetchUsage() async throws -> CodexUsageObservation {
    let data = try await self.runner.readRateLimits(
      executable: self.executable,
      timeout: self.timeout
    )
    let response = try Self.decodeRateLimits(from: data)
    guard let rateLimit = response.result?.rateLimits else {
      if response.error != nil { throw CodexUsageError.unavailable }
      throw CodexUsageError.invalidResponse
    }

    let primary = try rateLimit.primary.map(Self.usageWindow)
    let secondary = try rateLimit.secondary.map(Self.usageWindow)
    guard primary != nil || secondary != nil else { throw CodexUsageError.unavailable }

    return CodexUsageObservation(
      availability: .live,
      planType: rateLimit.planType,
      primary: primary,
      secondary: secondary,
      fetchedAt: self.now()
    )
  }

  private static func decodeRateLimits(from data: Data) throws -> RateLimitRPCResponse {
    guard let output = String(data: data, encoding: .utf8) else {
      throw CodexUsageError.invalidResponse
    }
    let decoder = JSONDecoder()
    for line in output.split(whereSeparator: \Character.isNewline) {
      guard let lineData = String(line).data(using: .utf8),
        let response = try? decoder.decode(RateLimitRPCResponse.self, from: lineData),
        response.id == ProcessCodexAppServerRunner.rateLimitRequestID
      else { continue }
      return response
    }
    throw CodexUsageError.invalidResponse
  }

  private static func usageWindow(_ value: RateLimitWindowResponse) throws -> CodexUsageWindow {
    guard value.usedPercent.isFinite, (0...100).contains(value.usedPercent),
      value.windowDurationMins > 0, value.resetsAt > 0
    else { throw CodexUsageError.invalidResponse }
    return CodexUsageWindow(
      usedPercent: value.usedPercent,
      windowDurationMinutes: value.windowDurationMins,
      resetsAt: Date(timeIntervalSince1970: TimeInterval(value.resetsAt))
    )
  }
}

public struct ProcessCodexAppServerRunner: CodexAppServerRunning, Sendable {
  fileprivate static let rateLimitRequestID = 2
  private static let maximumOutputBytes = 1_048_576

  public init() {}

  public func readRateLimits(executable: URL, timeout: TimeInterval) async throws -> Data {
    let worker = Task.detached(priority: .utility) {
      let fileManager = FileManager.default
      let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("moment-monitor-codex-\(UUID().uuidString)", isDirectory: true)
      try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
      try fileManager.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: temporaryDirectory.path
      )
      defer { try? fileManager.removeItem(at: temporaryDirectory) }

      let stdoutURL = temporaryDirectory.appendingPathComponent("stdout")
      let stderrURL = temporaryDirectory.appendingPathComponent("stderr")
      guard fileManager.createFile(atPath: stdoutURL.path, contents: nil),
        fileManager.createFile(atPath: stderrURL.path, contents: nil)
      else { throw CodexUsageError.commandFailed }
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stdoutURL.path)
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stderrURL.path)

      let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
      let stderrHandle = try FileHandle(forWritingTo: stderrURL)
      let inputPipe = Pipe()
      let inputHandle = inputPipe.fileHandleForWriting
      let process = Process()
      process.executableURL = executable
      process.arguments = ["app-server"]
      process.standardInput = inputPipe
      process.standardOutput = stdoutHandle
      process.standardError = stderrHandle
      process.environment = ProcessInfo.processInfo.environment.merging([
        "NO_COLOR": "1",
        "CLICOLOR": "0",
      ]) { _, new in new }

      defer {
        try? inputHandle.close()
        Self.stop(process)
        try? stdoutHandle.close()
        try? stderrHandle.close()
      }

      do {
        try process.run()
      } catch {
        throw CodexUsageError.commandFailed
      }

      try inputHandle.write(contentsOf: Self.rateLimitRequestPayload())

      let deadline = Date().addingTimeInterval(timeout)
      while process.isRunning {
        if Task.isCancelled { throw CancellationError() }
        try stdoutHandle.synchronize()
        let attributes = try fileManager.attributesOfItem(atPath: stdoutURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maximumOutputBytes else { throw CodexUsageError.invalidResponse }
        if size > 0 {
          let output = try Data(contentsOf: stdoutURL)
          if Self.containsRateLimitResponse(output) { return output }
        }
        if Date() >= deadline { throw CodexUsageError.timedOut }
        try await Task.sleep(for: .milliseconds(50))
      }

      try stdoutHandle.synchronize()
      let output = try Data(contentsOf: stdoutURL)
      if Self.containsRateLimitResponse(output) { return output }
      throw CodexUsageError.commandFailed
    }

    return try await withTaskCancellationHandler(
      operation: { try await worker.value },
      onCancel: { worker.cancel() }
    )
  }

  static func rateLimitRequestPayload() -> Data {
    let messages =
      [
        "{\"method\":\"initialize\",\"id\":0,\"params\":{\"clientInfo\":{\"name\":\"moment_monitor\",\"title\":\"Moment Monitor\",\"version\":\"0.4.8\"}}}",
        "{\"method\":\"initialized\",\"params\":{}}",
        "{\"method\":\"account/rateLimits/read\",\"id\":\(Self.rateLimitRequestID)}",
      ].joined(separator: "\n") + "\n"
    return Data(messages.utf8)
  }

  private static func containsRateLimitResponse(_ data: Data) -> Bool {
    guard let output = String(data: data, encoding: .utf8) else { return false }
    return output.split(whereSeparator: \Character.isNewline).contains { line in
      guard let lineData = String(line).data(using: .utf8),
        let value = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
        let id = value["id"] as? NSNumber
      else { return false }
      return id.intValue == Self.rateLimitRequestID
    }
  }

  private static func stop(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()

    let gracefulDeadline = Date().addingTimeInterval(0.25)
    while process.isRunning, Date() < gracefulDeadline {
      Thread.sleep(forTimeInterval: 0.01)
    }

    if process.isRunning {
      #if canImport(Darwin)
        _ = Darwin.kill(process.processIdentifier, SIGKILL)
      #elseif canImport(Glibc)
        _ = Glibc.kill(process.processIdentifier, SIGKILL)
      #endif
    }
    if process.isRunning { process.waitUntilExit() }
  }
}

private struct RateLimitRPCResponse: Decodable {
  let id: Int
  let result: RateLimitResultResponse?
  let error: RateLimitErrorResponse?
}

private struct RateLimitResultResponse: Decodable {
  let rateLimits: RateLimitResponse?
}

private struct RateLimitResponse: Decodable {
  let primary: RateLimitWindowResponse?
  let secondary: RateLimitWindowResponse?
  let planType: String?
}

private struct RateLimitWindowResponse: Decodable {
  let usedPercent: Double
  let windowDurationMins: Int
  let resetsAt: Int64
}

private struct RateLimitErrorResponse: Decodable {
  let code: Int?
}
