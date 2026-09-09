import Darwin
import Foundation

public enum AutomationWatchdogState: String, Codable, Equatable, Sendable {
  case idle
  case observing
  case suspectedStall = "suspected_stall"
  case unblocking
  case takeover
  case unavailable

  public var title: String {
    switch self {
    case .idle: "Idle"
    case .observing: "Observing"
    case .suspectedStall: "Checking possible stall"
    case .unblocking: "Recovery admitted"
    case .takeover: "Repair lane taking over"
    case .unavailable: "Observer unavailable"
    }
  }
}

public enum AutomationWatchdogAction: String, Codable, Equatable, Sendable {
  case observe
  case unblock
  case takeover
}

public struct AutomationWatchdogProcess: Codable, Equatable, Sendable {
  public let rootPresent: Bool
  public let descendantCount: Int
  public let maxCPUPercent: Double
  public let activityKind: String
  public let activity: String

  enum CodingKeys: String, CodingKey {
    case rootPresent = "root_present"
    case descendantCount = "descendant_count"
    case maxCPUPercent = "max_cpu_percent"
    case activityKind = "activity_kind"
    case activity
  }
}

public struct AutomationWatchdogDecision: Codable, Equatable, Sendable {
  public let action: AutomationWatchdogAction
  public let confidence: Double
  public let streak: Int
  public let requiredStreak: Int
  public let decidedAt: Date
  public let summary: String

  enum CodingKeys: String, CodingKey {
    case action, confidence, streak, summary
    case requiredStreak = "required_streak"
    case decidedAt = "decided_at"
  }
}

public struct AutomationWatchdogWorker: Codable, Equatable, Identifiable, Sendable {
  public let workerID: String
  public let issueNumber: Int
  public let leaseStatus: String
  public let leaseAgeSeconds: Int
  public let leaseRemainingSeconds: Int
  public let runtimeAvailable: Bool
  public let runtimeAgeSeconds: Int?
  public let phase: String
  public let role: String
  public let process: AutomationWatchdogProcess
  public let modelAvailable: Bool
  public let decision: AutomationWatchdogDecision?

  public var id: String { self.workerID }

  enum CodingKeys: String, CodingKey {
    case workerID = "worker_id"
    case issueNumber = "issue_number"
    case leaseStatus = "lease_status"
    case leaseAgeSeconds = "lease_age_seconds"
    case leaseRemainingSeconds = "lease_remaining_seconds"
    case runtimeAvailable = "runtime_available"
    case runtimeAgeSeconds = "runtime_age_seconds"
    case phase, role, process, decision
    case modelAvailable = "model_available"
  }
}

public struct AutomationWatchdogStatus: Codable, Equatable, Sendable {
  public let schema: String
  public let observedAt: Date
  public let state: AutomationWatchdogState
  public let model: String
  public let confidenceThreshold: Double
  public let requiredObservations: Int
  public let repository: String?
  public let workers: [AutomationWatchdogWorker]

  enum CodingKeys: String, CodingKey {
    case schema, state, model, repository, workers
    case observedAt = "observed_at"
    case confidenceThreshold = "confidence_threshold"
    case requiredObservations = "required_observations"
  }
}

public enum AutomationWatchdogAvailability: String, Codable, Equatable, Sendable {
  case absent
  case current
  case stale
  case invalid
}

public struct AutomationWatchdogObservation: Codable, Equatable, Sendable {
  public let availability: AutomationWatchdogAvailability
  public let status: AutomationWatchdogStatus?
  public let message: String?

  public init(
    availability: AutomationWatchdogAvailability,
    status: AutomationWatchdogStatus? = nil,
    message: String? = nil
  ) {
    self.availability = availability
    self.status = status
    self.message = message
  }

  public static let absent = Self(availability: .absent)
  public static func current(_ status: AutomationWatchdogStatus) -> Self {
    Self(availability: .current, status: status)
  }
  public static func stale(_ status: AutomationWatchdogStatus) -> Self {
    Self(availability: .stale, status: status, message: "Active observer status is stale.")
  }
  public static func invalid(_ message: String) -> Self {
    Self(availability: .invalid, message: message)
  }

  public var badgeLabel: String {
    switch self.availability {
    case .absent: "OFF"
    case .stale: "STALE"
    case .invalid: "INVALID"
    case .current:
      switch self.status?.state {
      case .idle: "IDLE"
      case .unavailable: "UNAVAILABLE"
      case .observing, .suspectedStall, .unblocking, .takeover: "LIVE"
      case nil: "UNAVAILABLE"
      }
    }
  }
}

private struct JSONDuplicateKeyValidator {
  private enum ParseError: Error { case malformed }

  private let bytes: [UInt8]
  private var index = 0

  init(data: Data) {
    self.bytes = Array(data)
  }

  mutating func validate() throws {
    try self.parseValue()
    self.skipWhitespace()
    guard self.index == self.bytes.count else { throw ParseError.malformed }
  }

  private mutating func parseValue() throws {
    self.skipWhitespace()
    guard let byte = self.peek() else { throw ParseError.malformed }
    switch byte {
    case 0x7B: try self.parseObject()
    case 0x5B: try self.parseArray()
    case 0x22: _ = try self.parseString()
    default: try self.parsePrimitive()
    }
  }

  private mutating func parseObject() throws {
    try self.expect(0x7B)
    self.skipWhitespace()
    if self.consume(0x7D) { return }
    var keys = Set<String>()
    while true {
      self.skipWhitespace()
      let key = try self.parseString()
      guard keys.insert(key).inserted else { throw ParseError.malformed }
      self.skipWhitespace()
      try self.expect(0x3A)
      try self.parseValue()
      self.skipWhitespace()
      if self.consume(0x7D) { return }
      try self.expect(0x2C)
    }
  }

  private mutating func parseArray() throws {
    try self.expect(0x5B)
    self.skipWhitespace()
    if self.consume(0x5D) { return }
    while true {
      try self.parseValue()
      self.skipWhitespace()
      if self.consume(0x5D) { return }
      try self.expect(0x2C)
    }
  }

  private mutating func parseString() throws -> String {
    let start = self.index
    try self.expect(0x22)
    var escaped = false
    while self.index < self.bytes.count {
      let byte = self.bytes[self.index]
      self.index += 1
      if escaped {
        escaped = false
      } else if byte == 0x5C {
        escaped = true
      } else if byte == 0x22 {
        let data = Data(self.bytes[start..<self.index])
        guard let value = try? JSONDecoder().decode(String.self, from: data) else {
          throw ParseError.malformed
        }
        return value
      }
    }
    throw ParseError.malformed
  }

  private mutating func parsePrimitive() throws {
    let start = self.index
    while let byte = self.peek(), !Self.isWhitespace(byte), ![0x2C, 0x5D, 0x7D].contains(byte) {
      self.index += 1
    }
    guard self.index > start else { throw ParseError.malformed }
  }

  private mutating func skipWhitespace() {
    while let byte = self.peek(), Self.isWhitespace(byte) { self.index += 1 }
  }

  private mutating func expect(_ byte: UInt8) throws {
    guard self.consume(byte) else { throw ParseError.malformed }
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard self.peek() == byte else { return false }
    self.index += 1
    return true
  }

  private func peek() -> UInt8? {
    self.index < self.bytes.count ? self.bytes[self.index] : nil
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    [0x09, 0x0A, 0x0D, 0x20].contains(byte)
  }
}

public struct AutomationWatchdogStatusReader: Sendable {
  public static let maximumBytes = 32 * 1024
  public static let freshnessInterval: TimeInterval = 5 * 60

  private let fileURL: URL
  private let currentUserID: UInt32
  private let now: @Sendable () -> Date

  public init(
    fileURL: URL,
    currentUserID: UInt32,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.fileURL = fileURL
    self.currentUserID = currentUserID
    self.now = now
  }

  public static func live() -> Self {
    let root = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/MomentAutomationMaintenance/watchdog")
    return Self(
      fileURL: root.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )
  }

  public func read(repository: RepositoryCoordinate) async -> AutomationWatchdogObservation {
    do {
      guard let data = try self.readSecurely() else { return .absent }
      let status = try Self.decodeAndValidate(data)
      guard status.repository?.caseInsensitiveCompare(repository.fullName) == .orderedSame else {
        return .absent
      }
      let age = self.now().timeIntervalSince(status.observedAt)
      guard age >= -30 else { return .invalid("Active observer timestamp is in the future.") }
      if age > Self.freshnessInterval { return .stale(status) }
      return .current(status)
    } catch let error as AutomationWatchdogReadError {
      return .invalid(error.errorDescription ?? "Active observer status is invalid.")
    } catch {
      return .invalid("Active observer status could not be read safely.")
    }
  }

  private func readSecurely() throws -> Data? {
    let descriptor = Darwin.open(
      self.fileURL.path,
      O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
    )
    if descriptor < 0 {
      if errno == ENOENT { return nil }
      if errno == ELOOP { throw AutomationWatchdogReadError.symbolicLink }
      throw AutomationWatchdogReadError.unreadable
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var metadata = stat()
    guard Darwin.fstat(descriptor, &metadata) == 0 else {
      throw AutomationWatchdogReadError.unreadable
    }
    guard metadata.st_mode & S_IFMT == S_IFREG else {
      throw AutomationWatchdogReadError.notRegularFile
    }
    guard metadata.st_uid == self.currentUserID else {
      throw AutomationWatchdogReadError.wrongOwner
    }
    guard metadata.st_mode & 0o077 == 0 else {
      throw AutomationWatchdogReadError.unsafePermissions
    }
    guard metadata.st_size > 0, metadata.st_size <= Self.maximumBytes,
      let data = try handle.read(upToCount: Self.maximumBytes + 1),
      !data.isEmpty, data.count <= Self.maximumBytes
    else { throw AutomationWatchdogReadError.sizeLimit }
    return data
  }

  static func decodeAndValidate(_ data: Data) throws -> AutomationWatchdogStatus {
    guard data.count <= Self.maximumBytes else { throw AutomationWatchdogReadError.sizeLimit }
    var duplicateKeyValidator = JSONDuplicateKeyValidator(data: data)
    do { try duplicateKeyValidator.validate() } catch {
      throw AutomationWatchdogReadError.invalidJSON
    }
    guard
      let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw AutomationWatchdogReadError.invalidJSON }
    guard Set(raw.keys) == topLevelKeys else { throw AutomationWatchdogReadError.unknownFields }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601Flexible
    let status: AutomationWatchdogStatus
    do { status = try decoder.decode(AutomationWatchdogStatus.self, from: data) } catch {
      throw AutomationWatchdogReadError.invalidJSON
    }
    guard status.schema == "moment.automation-watchdog.v1",
      isBoundedIdentifier(status.model, maximum: 128),
      (0...1).contains(status.confidenceThreshold),
      status.confidenceThreshold >= 0.8,
      status.requiredObservations >= 2, status.requiredObservations <= 10,
      status.repository.map({
        $0.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
      }) ?? true,
      status.workers.count <= 2,
      Set(status.workers.map(\.workerID)).count == status.workers.count,
      Set(status.workers.map(\.issueNumber)).count == status.workers.count
    else { throw AutomationWatchdogReadError.unsupportedSchema }
    guard let rawWorkers = raw["workers"] as? [[String: Any]],
      rawWorkers.count == status.workers.count
    else { throw AutomationWatchdogReadError.invalidWorker }
    for (worker, object) in zip(status.workers, rawWorkers) {
      let allowed = workerKeys.union(worker.decision == nil ? [] : ["decision"])
      guard Set(object.keys) == allowed,
        ["worker-0", "worker-1"].contains(worker.workerID),
        worker.issueNumber > 0,
        ["running", "continuing"].contains(worker.leaseStatus),
        worker.leaseAgeSeconds >= 0,
        (-7 * 24 * 60 * 60...7 * 24 * 60 * 60).contains(worker.leaseRemainingSeconds),
        worker.runtimeAgeSeconds.map({ $0 >= 0 }) ?? true,
        isBoundedRuntimeLabel(worker.phase), isBoundedRuntimeLabel(worker.role),
        worker.process.descendantCount >= 0,
        (0...999).contains(worker.process.maxCPUPercent),
        ["none", "compiler", "build", "vcs", "agent", "controller", "shell", "other"].contains(
          worker.process.activityKind),
        ["absent", "waiting", "working"].contains(worker.process.activity),
        let process = object["process"] as? [String: Any], Set(process.keys) == processKeys,
        processFieldsAreCoherent(worker.process),
        worker.modelAvailable == (worker.decision != nil),
        runtimeFieldsAreCoherent(worker)
      else { throw AutomationWatchdogReadError.invalidWorker }
      if let decision = worker.decision {
        let confidentActionable =
          [.unblock, .takeover].contains(decision.action)
          && decision.confidence >= status.confidenceThreshold
        guard let rawDecision = object["decision"] as? [String: Any],
          Set(rawDecision.keys) == decisionKeys,
          (0...1).contains(decision.confidence),
          decision.streak >= 0, decision.streak <= decision.requiredStreak,
          decision.requiredStreak == status.requiredObservations,
          confidentActionable ? decision.streak >= 1 : decision.streak == 0,
          decision.decidedAt <= status.observedAt.addingTimeInterval(30),
          decision.decidedAt >= status.observedAt.addingTimeInterval(-freshnessInterval),
          decision.summary == decisionSummary[decision.action]
        else { throw AutomationWatchdogReadError.invalidDecision }
      }
    }
    guard stateIsCoherent(status) else { throw AutomationWatchdogReadError.unsupportedSchema }
    return status
  }

  private static func isBoundedIdentifier(_ value: String, maximum: Int) -> Bool {
    !value.isEmpty && value.count <= maximum
      && value.allSatisfy(\.isASCII) && value.allSatisfy(\.isWholeNumberOrIdentifierPunctuation)
  }

  private static func isBoundedRuntimeLabel(_ value: String) -> Bool {
    value.range(of: #"^(?:unavailable|[a-z][a-z0-9_]{0,63})$"#, options: .regularExpression)
      != nil
  }

  private static func runtimeFieldsAreCoherent(_ worker: AutomationWatchdogWorker) -> Bool {
    if worker.runtimeAvailable {
      return worker.runtimeAgeSeconds != nil
        && worker.phase != "unavailable" && worker.role != "unavailable"
    }
    return worker.runtimeAgeSeconds == nil
      && worker.phase == "unavailable" && worker.role == "unavailable"
  }

  private static func processFieldsAreCoherent(_ process: AutomationWatchdogProcess) -> Bool {
    if process.activity == "absent" {
      return !process.rootPresent && process.descendantCount == 0
        && process.maxCPUPercent == 0 && process.activityKind == "none"
    }
    return (process.activity != "waiting" || process.maxCPUPercent < 1)
      && process.activityKind != "none"
      && (process.rootPresent || process.descendantCount > 0)
  }

  private static func stateIsCoherent(_ status: AutomationWatchdogStatus) -> Bool {
    let decisions = status.workers.compactMap(\.decision)
    let admitted = decisions.filter {
      $0.confidence >= status.confidenceThreshold && $0.streak >= status.requiredObservations
        && [.unblock, .takeover].contains($0.action)
    }
    switch status.state {
    case .idle:
      return status.workers.isEmpty
    case .observing:
      return !status.workers.isEmpty && !decisions.isEmpty
        && decisions.allSatisfy { $0.action == .observe }
    case .suspectedStall:
      return !status.workers.isEmpty && admitted.isEmpty
        && decisions.contains { [.unblock, .takeover].contains($0.action) }
    case .unblocking:
      return admitted.contains { $0.action == .unblock }
        && !admitted.contains { $0.action == .takeover }
    case .takeover:
      return admitted.contains { $0.action == .takeover }
    case .unavailable:
      return decisions.isEmpty && status.workers.allSatisfy { !$0.modelAvailable }
    }
  }

  private static let decisionSummary: [AutomationWatchdogAction: String] = [
    .observe: "Local model found no actionable stall.",
    .unblock: "Local model recommends bounded recovery.",
    .takeover: "Local model recommends isolated repair ownership.",
  ]

  private static let topLevelKeys: Set<String> = [
    "schema", "observed_at", "state", "model", "confidence_threshold",
    "required_observations", "repository", "workers",
  ]
  private static let workerKeys: Set<String> = [
    "worker_id", "issue_number", "lease_status", "lease_age_seconds",
    "lease_remaining_seconds", "runtime_available", "runtime_age_seconds",
    "phase", "role", "process", "model_available",
  ]
  private static let processKeys: Set<String> = [
    "root_present", "descendant_count", "max_cpu_percent", "activity_kind", "activity",
  ]
  private static let decisionKeys: Set<String> = [
    "action", "confidence", "streak", "required_streak", "decided_at", "summary",
  ]
}

extension Character {
  fileprivate var isWholeNumberOrIdentifierPunctuation: Bool {
    self.isLetter || self.isNumber || "._-:".contains(self)
  }
}

extension JSONDecoder.DateDecodingStrategy {
  fileprivate static var iso8601Flexible: JSONDecoder.DateDecodingStrategy {
    .custom { decoder in
      let container = try decoder.singleValueContainer()
      let text = try container.decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: text) { return date }
      let whole = ISO8601DateFormatter()
      whole.formatOptions = [.withInternetDateTime]
      if let date = whole.date(from: text) { return date }
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp")
    }
  }
}

enum AutomationWatchdogReadError: LocalizedError {
  case symbolicLink, unreadable, notRegularFile, wrongOwner, unsafePermissions, sizeLimit
  case invalidJSON, unknownFields, unsupportedSchema, invalidWorker, invalidDecision

  var errorDescription: String? {
    switch self {
    case .symbolicLink: "Active observer status cannot be a symbolic link."
    case .unreadable: "Active observer status is unreadable."
    case .notRegularFile: "Active observer status is not a regular file."
    case .wrongOwner: "Active observer status has the wrong owner."
    case .unsafePermissions: "Active observer status permissions are unsafe."
    case .sizeLimit: "Active observer status exceeds its size boundary."
    case .invalidJSON: "Active observer status is not valid JSON."
    case .unknownFields: "Active observer status contains private or unknown fields."
    case .unsupportedSchema: "Active observer status uses an unsupported contract."
    case .invalidWorker: "Active observer worker state is invalid."
    case .invalidDecision: "Active observer decision is invalid."
    }
  }
}
