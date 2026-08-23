import Foundation

#if os(macOS)
  import Darwin
#endif

public protocol AutomationRuntimeStatusReading: Sendable {
  func read(repository: RepositoryCoordinate) async -> AutomationRuntimeObservation
}

public struct NoAutomationRuntimeStatusReader: AutomationRuntimeStatusReading {
  public init() {}

  public func read(repository: RepositoryCoordinate) async -> AutomationRuntimeObservation {
    .absent
  }
}

public struct AutomationRuntimeStatusReader: AutomationRuntimeStatusReading, Sendable {
  public static let maximumBytes = 16 * 1024

  private let fileURL: URL
  private let currentUserID: UInt32
  private let processIsAlive: @Sendable (Int32) -> Bool

  public init(
    fileURL: URL,
    currentUserID: UInt32,
    processIsAlive: @escaping @Sendable (Int32) -> Bool
  ) {
    self.fileURL = fileURL
    self.currentUserID = currentUserID
    self.processIsAlive = processIsAlive
  }

  public static func live(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let stateDirectory: URL
    if let explicit = environment["MOMENT_WORK_STATE_DIR"], !explicit.isEmpty {
      stateDirectory = URL(fileURLWithPath: explicit, isDirectory: true)
    } else {
      stateDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MomentAutomation", isDirectory: true)
    }
    return Self(
      fileURL: stateDirectory.appendingPathComponent("runtime/current.json"),
      currentUserID: Self.userID,
      processIsAlive: Self.isProcessAlive
    )
  }

  public func read(repository: RepositoryCoordinate) async -> AutomationRuntimeObservation {
    do {
      guard let data = try self.readSecurely() else { return .absent }
      let status = try Self.decodeAndValidate(data)
      guard status.repository.caseInsensitiveCompare(repository.fullName) == .orderedSame else {
        return .absent
      }
      if status.outcome == .active {
        guard self.processIsAlive(status.runnerPID) else {
          return .stale(status, message: "The controller process is no longer running.")
        }
        return .live(status)
      }
      return .terminal(status)
    } catch let error as RuntimeStatusReadError {
      return .invalid(error.errorDescription ?? "Local runtime status is invalid.")
    } catch {
      return .invalid("Local runtime status could not be read safely.")
    }
  }

  private func readSecurely() throws -> Data? {
    #if os(macOS)
      let descriptor = Darwin.open(self.fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
      if descriptor < 0 {
        if errno == ENOENT { return nil }
        if errno == ELOOP { throw RuntimeStatusReadError.symbolicLink }
        throw RuntimeStatusReadError.unreadable
      }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      defer { try? handle.close() }

      var metadata = stat()
      guard Darwin.fstat(descriptor, &metadata) == 0 else {
        throw RuntimeStatusReadError.unreadable
      }
      guard (metadata.st_mode & S_IFMT) == S_IFREG else {
        throw RuntimeStatusReadError.notRegularFile
      }
      guard metadata.st_uid == self.currentUserID else {
        throw RuntimeStatusReadError.wrongOwner
      }
      guard (metadata.st_mode & 0o077) == 0 else {
        throw RuntimeStatusReadError.unsafePermissions
      }
      guard metadata.st_size > 0, metadata.st_size <= Self.maximumBytes else {
        throw RuntimeStatusReadError.sizeLimit
      }
      guard let data = try handle.read(upToCount: Self.maximumBytes + 1), !data.isEmpty,
        data.count <= Self.maximumBytes
      else {
        throw RuntimeStatusReadError.sizeLimit
      }
      return data
    #else
      return nil
    #endif
  }

  static func decodeAndValidate(_ data: Data) throws -> AutomationRuntimeStatus {
    guard data.count <= Self.maximumBytes else { throw RuntimeStatusReadError.sizeLimit }
    let raw = try JSONSerialization.jsonObject(with: data)
    guard let object = raw as? [String: Any] else { throw RuntimeStatusReadError.invalidJSON }
    guard Set(object.keys) == Self.allowedKeys else {
      throw RuntimeStatusReadError.unknownFields
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: value) { return date }
      let wholeSeconds = ISO8601DateFormatter()
      wholeSeconds.formatOptions = [.withInternetDateTime]
      if let date = wholeSeconds.date(from: value) { return date }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Runtime timestamp is not ISO 8601."
      )
    }
    let status: AutomationRuntimeStatus
    do {
      status = try decoder.decode(AutomationRuntimeStatus.self, from: data)
    } catch {
      throw RuntimeStatusReadError.invalidJSON
    }
    try Self.validate(status)
    return status
  }

  private static func validate(_ status: AutomationRuntimeStatus) throws {
    guard status.schemaVersion == 1,
      status.formatVersion == "moment.automation-runtime.v1"
    else { throw RuntimeStatusReadError.unsupportedSchema }
    guard Self.isRepository(status.repository),
      Self.isRunID(status.runID),
      status.issueNumber > 0,
      status.pullRequestNumber.map({ $0 > 0 }) ?? true,
      status.runnerPID > 0,
      status.sequence > 0
    else { throw RuntimeStatusReadError.invalidIdentity }
    guard status.startedAt <= status.phaseStartedAt,
      status.phaseStartedAt <= status.updatedAt
    else { throw RuntimeStatusReadError.invalidTimeline }
    guard (status.roundNumber == nil) == (status.totalRounds == nil) else {
      throw RuntimeStatusReadError.invalidRound
    }
    if let round = status.roundNumber, let total = status.totalRounds {
      guard round > 0, total > 0, round <= total else {
        throw RuntimeStatusReadError.invalidRound
      }
    }
    guard status.repairAttempt.map({ $0 > 0 }) ?? true else {
      throw RuntimeStatusReadError.invalidRound
    }
    for sha in [status.baseSHA, status.headSHA].compactMap({ $0 }) {
      guard sha.count == 40, sha.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
        throw RuntimeStatusReadError.invalidIdentity
      }
    }
    try Self.validatePhaseSemantics(status)
  }

  private static func validatePhaseSemantics(_ status: AutomationRuntimeStatus) throws {
    let terminalOutcomeByPhase: [AutomationRuntimePhase: AutomationRuntimeOutcome] = [
      .completed: .completed,
      .blocked: .blocked,
      .failed: .failed,
      .stoppedNoChange: .stopped,
    ]
    if let expected = terminalOutcomeByPhase[status.phase] {
      guard status.outcome == expected,
        let lastActivePhase = status.lastActivePhase,
        !lastActivePhase.isTerminal
      else { throw RuntimeStatusReadError.invalidPhase }
    } else {
      guard status.outcome == .active, status.lastActivePhase == nil else {
        throw RuntimeStatusReadError.invalidPhase
      }
    }

    let expected: (AutomationRuntimeModel?, AutomationRuntimeRole?)
    switch status.phase {
    case .lunaImplementation:
      expected = (.luna, .implementer)
    case .solCIRepair, .solHighUnblock, .solPRFastRepair, .solReviewRepair:
      expected = (.sol, .repairer)
    case .solReview:
      expected = (.sol, .reviewer)
    case .lunaVerification:
      expected = (.luna, .reviewer)
    case .prFast:
      expected = (nil, .validator)
    case .publishingBranch, .creatingPR, .verifyingExactHead, .mergingPR, .closingIssue:
      expected = (nil, .publisher)
    case .preparingWorkspace, .adoptingExistingPR, .committingCandidate, .completed, .blocked,
      .failed, .stoppedNoChange:
      expected = (nil, .controller)
    }
    guard status.model == expected.0, status.role == expected.1 else {
      throw RuntimeStatusReadError.invalidPhase
    }
  }

  private static func isRepository(_ value: String) -> Bool {
    let parts = value.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
    return parts.allSatisfy { part in
      !part.isEmpty && part.unicodeScalars.allSatisfy(allowed.contains)
    }
  }

  private static func isRunID(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 128 else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.:-"))
    return value.unicodeScalars.allSatisfy(allowed.contains)
  }

  private static let allowedKeys: Set<String> = [
    "schema_version", "format_version", "repository", "run_id", "issue_number",
    "pull_request_number", "mode", "phase", "last_active_phase", "outcome", "model", "role",
    "round_number",
    "total_rounds", "repair_attempt", "runner_pid", "sequence", "started_at",
    "phase_started_at", "updated_at", "base_sha", "head_sha",
  ]

  #if os(macOS)
    private static var userID: UInt32 { Darwin.getuid() }

    private static func isProcessAlive(_ processID: Int32) -> Bool {
      errno = 0
      return Darwin.kill(processID, 0) == 0 || errno == EPERM
    }
  #else
    private static var userID: UInt32 { 0 }
    private static func isProcessAlive(_ processID: Int32) -> Bool { false }
  #endif
}

enum RuntimeStatusReadError: LocalizedError {
  case symbolicLink
  case unreadable
  case notRegularFile
  case wrongOwner
  case unsafePermissions
  case sizeLimit
  case invalidJSON
  case unknownFields
  case unsupportedSchema
  case invalidIdentity
  case invalidTimeline
  case invalidRound
  case invalidPhase

  var errorDescription: String? {
    switch self {
    case .symbolicLink: "Local runtime status must not be a symbolic link."
    case .unreadable: "Local runtime status could not be opened safely."
    case .notRegularFile: "Local runtime status is not a regular file."
    case .wrongOwner: "Local runtime status is not owned by the current user."
    case .unsafePermissions: "Local runtime status permissions are too broad."
    case .sizeLimit: "Local runtime status exceeds its size boundary."
    case .invalidJSON: "Local runtime status is malformed."
    case .unknownFields: "Local runtime status contains fields outside the public contract."
    case .unsupportedSchema: "Local runtime status uses an unsupported schema."
    case .invalidIdentity: "Local runtime status has an invalid run identity."
    case .invalidTimeline: "Local runtime status timestamps are inconsistent."
    case .invalidRound: "Local runtime status has an invalid round counter."
    case .invalidPhase: "Local runtime status phase, model, role, and outcome disagree."
    }
  }
}
