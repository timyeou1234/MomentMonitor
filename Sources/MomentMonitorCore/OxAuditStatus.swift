import Darwin
import Foundation

public enum OxAuditState: String, Codable, Equatable, Sendable {
  case starting
  case probing
  case available
  case scanning
  case backoff
  case completed
  case stopped

  public var title: String {
    switch self {
    case .starting: "Starting"
    case .probing: "Checking free route"
    case .available: "Free route available"
    case .scanning: "Reviewing Issues"
    case .backoff: "Waiting to retry"
    case .completed: "Issue sweep completed"
    case .stopped: "Stopped"
    }
  }

  public var isTerminal: Bool { self == .completed || self == .stopped }
}

public struct OxAuditStatus: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let formatVersion: String
  public let model: String
  public let state: OxAuditState
  public let currentIssue: Int?
  public let completedCount: Int
  public let totalCount: Int
  public let lastHTTPStatus: Int?
  public let updatedAt: Date
  public let nextAttemptAt: Date?

  public init(
    schemaVersion: Int = 1,
    formatVersion: String = "moment.ox-audit.v1",
    model: String = "Ox Alpha Free",
    state: OxAuditState,
    currentIssue: Int? = nil,
    completedCount: Int,
    totalCount: Int,
    lastHTTPStatus: Int? = nil,
    updatedAt: Date,
    nextAttemptAt: Date? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.formatVersion = formatVersion
    self.model = model
    self.state = state
    self.currentIssue = currentIssue
    self.completedCount = completedCount
    self.totalCount = totalCount
    self.lastHTTPStatus = lastHTTPStatus
    self.updatedAt = updatedAt
    self.nextAttemptAt = nextAttemptAt
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case formatVersion = "format_version"
    case model
    case state
    case currentIssue = "current_issue"
    case completedCount = "completed_count"
    case totalCount = "total_count"
    case lastHTTPStatus = "last_http_status"
    case updatedAt = "updated_at"
    case nextAttemptAt = "next_attempt_at"
  }
}

public enum OxAuditAvailability: String, Codable, Equatable, Sendable {
  case absent
  case current
  case stale
  case invalid
}

public struct OxAuditObservation: Codable, Equatable, Sendable {
  public let availability: OxAuditAvailability
  public let status: OxAuditStatus?
  public let message: String?

  public init(
    availability: OxAuditAvailability,
    status: OxAuditStatus? = nil,
    message: String? = nil
  ) {
    self.availability = availability
    self.status = status
    self.message = message
  }

  public static let absent = Self(availability: .absent)
  public static func current(_ status: OxAuditStatus) -> Self {
    Self(availability: .current, status: status)
  }
  public static func stale(_ status: OxAuditStatus) -> Self {
    Self(
      availability: .stale,
      status: status,
      message: "Ox status has not refreshed recently."
    )
  }
  public static func invalid(_ message: String) -> Self {
    Self(availability: .invalid, message: message)
  }
}

public struct OxAuditStatusReader: Sendable {
  public static let maximumBytes = 4 * 1024
  public static let freshnessInterval: TimeInterval = 45 * 60

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
    let directory = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/MomentAutomation/runtime")
    return Self(
      fileURL: directory.appendingPathComponent("ox-current.json"),
      currentUserID: Darwin.getuid()
    )
  }

  public func read() async -> OxAuditObservation {
    do {
      guard let data = try self.readSecurely() else { return .absent }
      let status = try Self.decodeAndValidate(data)
      if !status.state.isTerminal,
        self.now().timeIntervalSince(status.updatedAt) > Self.freshnessInterval
      {
        return .stale(status)
      }
      return .current(status)
    } catch let error as OxAuditReadError {
      return .invalid(error.errorDescription ?? "Ox status is invalid.")
    } catch {
      return .invalid("Ox status could not be read safely.")
    }
  }

  private func readSecurely() throws -> Data? {
    let descriptor = Darwin.open(self.fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    if descriptor < 0 {
      if errno == ENOENT { return nil }
      if errno == ELOOP { throw OxAuditReadError.symbolicLink }
      throw OxAuditReadError.unreadable
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var metadata = stat()
    guard Darwin.fstat(descriptor, &metadata) == 0 else { throw OxAuditReadError.unreadable }
    guard (metadata.st_mode & S_IFMT) == S_IFREG else { throw OxAuditReadError.notRegularFile }
    guard metadata.st_uid == self.currentUserID else { throw OxAuditReadError.wrongOwner }
    guard (metadata.st_mode & 0o077) == 0 else { throw OxAuditReadError.unsafePermissions }
    guard metadata.st_size > 0, metadata.st_size <= Self.maximumBytes,
      let data = try handle.read(upToCount: Self.maximumBytes + 1),
      !data.isEmpty, data.count <= Self.maximumBytes
    else { throw OxAuditReadError.sizeLimit }
    return data
  }

  static func decodeAndValidate(_ data: Data) throws -> OxAuditStatus {
    guard data.count <= Self.maximumBytes else { throw OxAuditReadError.sizeLimit }
    let raw = try JSONSerialization.jsonObject(with: data)
    guard let object = raw as? [String: Any] else { throw OxAuditReadError.invalidJSON }
    guard Set(object.keys) == Self.allowedKeys else { throw OxAuditReadError.unknownFields }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
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
    let status: OxAuditStatus
    do {
      status = try decoder.decode(OxAuditStatus.self, from: data)
    } catch {
      throw OxAuditReadError.invalidJSON
    }
    guard status.schemaVersion == 1,
      status.formatVersion == "moment.ox-audit.v1",
      status.model == "Ox Alpha Free"
    else { throw OxAuditReadError.unsupportedSchema }
    guard status.completedCount >= 0,
      status.totalCount >= status.completedCount,
      status.totalCount <= 500,
      status.currentIssue.map({ $0 > 0 }) ?? true,
      status.lastHTTPStatus.map({ (100...599).contains($0) }) ?? true
    else { throw OxAuditReadError.invalidProgress }
    if status.state == .scanning {
      guard status.currentIssue != nil, status.totalCount > 0 else {
        throw OxAuditReadError.invalidProgress
      }
    }
    if status.state == .backoff {
      guard let next = status.nextAttemptAt, next >= status.updatedAt else {
        throw OxAuditReadError.invalidTimeline
      }
    } else if status.nextAttemptAt != nil {
      throw OxAuditReadError.invalidTimeline
    }
    if status.state == .completed, status.completedCount != status.totalCount {
      throw OxAuditReadError.invalidProgress
    }
    return status
  }

  private static let allowedKeys: Set<String> = [
    "schema_version", "format_version", "model", "state", "current_issue",
    "completed_count", "total_count", "last_http_status", "updated_at", "next_attempt_at",
  ]
}

enum OxAuditReadError: LocalizedError {
  case symbolicLink, unreadable, notRegularFile, wrongOwner, unsafePermissions, sizeLimit
  case invalidJSON, unknownFields, unsupportedSchema, invalidProgress, invalidTimeline

  var errorDescription: String? {
    switch self {
    case .symbolicLink: "Ox status must not be a symbolic link."
    case .unreadable: "Ox status could not be opened safely."
    case .notRegularFile: "Ox status is not a regular file."
    case .wrongOwner: "Ox status has the wrong owner."
    case .unsafePermissions: "Ox status permissions are too broad."
    case .sizeLimit: "Ox status exceeds its size boundary."
    case .invalidJSON: "Ox status is malformed."
    case .unknownFields: "Ox status contains fields outside the public contract."
    case .unsupportedSchema: "Ox status uses an unsupported schema or model identity."
    case .invalidProgress: "Ox progress values are inconsistent."
    case .invalidTimeline: "Ox retry timing is inconsistent."
    }
  }
}
