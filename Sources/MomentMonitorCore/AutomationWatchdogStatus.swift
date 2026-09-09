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

  public func read() async -> AutomationWatchdogObservation {
    do {
      guard let data = try self.readSecurely() else { return .absent }
      let status = try Self.decodeAndValidate(data)
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
    let descriptor = Darwin.open(self.fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
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
    guard data.count <= Self.maximumBytes,
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
      !status.model.isEmpty, status.model.count <= 128,
      (0...1).contains(status.confidenceThreshold),
      status.confidenceThreshold >= 0.8,
      status.requiredObservations >= 2, status.requiredObservations <= 10,
      status.repository.map({
        $0.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
      }) ?? true,
      status.workers.count <= 8
    else { throw AutomationWatchdogReadError.unsupportedSchema }
    guard let rawWorkers = raw["workers"] as? [[String: Any]],
      rawWorkers.count == status.workers.count
    else { throw AutomationWatchdogReadError.invalidWorker }
    for (worker, object) in zip(status.workers, rawWorkers) {
      let allowed = workerKeys.union(worker.decision == nil ? [] : ["decision"])
      guard Set(object.keys) == allowed,
        worker.workerID.range(of: #"^worker-[0-9]+$"#, options: .regularExpression) != nil,
        worker.issueNumber > 0,
        worker.leaseAgeSeconds >= 0,
        worker.runtimeAgeSeconds.map({ $0 >= 0 }) ?? true,
        worker.phase.count <= 64, worker.role.count <= 64,
        worker.process.descendantCount >= 0,
        (0...999).contains(worker.process.maxCPUPercent),
        ["none", "compiler", "build", "vcs", "agent", "controller", "shell", "other"].contains(
          worker.process.activityKind),
        ["absent", "waiting", "working"].contains(worker.process.activity),
        let process = object["process"] as? [String: Any], Set(process.keys) == processKeys
      else { throw AutomationWatchdogReadError.invalidWorker }
      if let decision = worker.decision {
        guard let rawDecision = object["decision"] as? [String: Any],
          Set(rawDecision.keys) == decisionKeys,
          (0...1).contains(decision.confidence),
          decision.streak >= 0, decision.streak <= decision.requiredStreak,
          decision.requiredStreak == status.requiredObservations,
          decision.summary.count <= 240
        else { throw AutomationWatchdogReadError.invalidDecision }
      }
    }
    return status
  }

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
