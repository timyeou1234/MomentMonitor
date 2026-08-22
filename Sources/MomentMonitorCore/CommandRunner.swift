import Foundation

public struct CommandResult: Equatable, Sendable {
  public let exitCode: Int32
  public let standardOutput: Data
  public let standardError: Data

  public init(exitCode: Int32, standardOutput: Data, standardError: Data) {
    self.exitCode = exitCode
    self.standardOutput = standardOutput
    self.standardError = standardError
  }
}

public protocol CommandRunning: Sendable {
  func run(
    executable: URL,
    arguments: [String],
    environment: [String: String],
    timeout: TimeInterval
  ) async throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
  public init() {}

  public func run(
    executable: URL,
    arguments: [String],
    environment: [String: String],
    timeout: TimeInterval
  ) async throws -> CommandResult {
    let worker = Task.detached(priority: .utility) {
      let fileManager = FileManager.default
      let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("moment-monitor-\(UUID().uuidString)", isDirectory: true)
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
      else {
        throw MomentMonitorError.invalidResponse("Could not create command output files.")
      }
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stdoutURL.path)
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stderrURL.path)

      let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
      let stderrHandle = try FileHandle(forWritingTo: stderrURL)
      defer {
        try? stdoutHandle.close()
        try? stderrHandle.close()
      }

      let process = Process()
      process.executableURL = executable
      process.arguments = arguments
      process.standardOutput = stdoutHandle
      process.standardError = stderrHandle
      process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new
      }

      try process.run()
      let deadline = Date().addingTimeInterval(timeout)

      while process.isRunning {
        if Task.isCancelled {
          process.terminate()
          process.waitUntilExit()
          throw CancellationError()
        }
        if Date() >= deadline {
          process.terminate()
          process.waitUntilExit()
          throw MomentMonitorError.commandTimedOut(seconds: timeout)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
      }

      try stdoutHandle.synchronize()
      try stderrHandle.synchronize()
      let stdout = try Data(contentsOf: stdoutURL)
      let stderr = try Data(contentsOf: stderrURL)

      return CommandResult(
        exitCode: process.terminationStatus,
        standardOutput: stdout,
        standardError: stderr
      )
    }

    return try await withTaskCancellationHandler(
      operation: { try await worker.value },
      onCancel: { worker.cancel() }
    )
  }
}

public enum GHExecutableLocator {
  public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment)
    throws -> URL
  {
    let fileManager = FileManager.default
    var candidates: [String] = []

    if let explicit = environment["MOMENT_MONITOR_GH_PATH"], !explicit.isEmpty {
      candidates.append(explicit)
    }

    candidates.append(contentsOf: [
      "/opt/homebrew/bin/gh",
      "/usr/local/bin/gh",
      "/usr/bin/gh",
      "/opt/local/bin/gh",
    ])

    if let path = environment["PATH"] {
      candidates.append(
        contentsOf:
          path
          .split(separator: ":")
          .map { String($0) + "/gh" })
    }

    for candidate in candidates {
      if fileManager.isExecutableFile(atPath: candidate) {
        return URL(fileURLWithPath: candidate)
      }
    }

    throw MomentMonitorError.executableNotFound("GitHub CLI (gh)")
  }
}
