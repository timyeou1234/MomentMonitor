import Darwin
import Foundation

public struct ProductDevCutoverRuntimePaths: Equatable, Sendable {
  public let handoffActivation: URL
  public let engineActivation: URL
  public let authorityDirectory: URL
  public let serviceEntry: URL
  public let runtimeStatus: URL
  public let controllerPID: URL

  public init(
    handoffActivation: URL,
    engineActivation: URL,
    authorityDirectory: URL,
    serviceEntry: URL,
    runtimeStatus: URL,
    controllerPID: URL
  ) {
    self.handoffActivation = handoffActivation
    self.engineActivation = engineActivation
    self.authorityDirectory = authorityDirectory
    self.serviceEntry = serviceEntry
    self.runtimeStatus = runtimeStatus
    self.controllerPID = controllerPID
  }

  public static func live(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let productDev = homeDirectory.appendingPathComponent(
      "Library/Application Support/ProductDev",
      isDirectory: true
    )
    let engineRuntime = productDev.appendingPathComponent("EngineRuntime", isDirectory: true)
    let authority = engineRuntime.appendingPathComponent("current", isDirectory: true)
    let momentState: URL
    if let explicit = environment["MOMENT_WORK_STATE_DIR"], !explicit.isEmpty {
      momentState = URL(fileURLWithPath: explicit, isDirectory: true)
    } else {
      momentState = homeDirectory.appendingPathComponent(
        "Library/Application Support/MomentAutomation",
        isDirectory: true
      )
    }
    return Self(
      handoffActivation: productDev.appendingPathComponent("activation.json"),
      engineActivation: engineRuntime.appendingPathComponent("activation.json"),
      authorityDirectory: authority,
      serviceEntry: authority.appendingPathComponent("Engine/productdev_runtime.py"),
      runtimeStatus: productDev.appendingPathComponent(
        "Profiles/moments-v2/runtime/current.json"
      ),
      controllerPID: momentState.appendingPathComponent("moment-local-work.lock.d/pid")
    )
  }
}

public struct ProductDevCutoverRuntimeStatusReader: AutomationRuntimeStatusReading, Sendable {
  public static let maximumActivationBytes = 16 * 1024
  public static let maximumRuntimeBytes = 16 * 1024

  private let legacyReader: any AutomationRuntimeStatusReading
  private let paths: ProductDevCutoverRuntimePaths
  private let currentUserID: UInt32
  private let processIsAlive: @Sendable (Int32) -> Bool
  private let now: @Sendable () -> Date

  public init(
    legacyReader: any AutomationRuntimeStatusReading,
    paths: ProductDevCutoverRuntimePaths,
    currentUserID: UInt32,
    processIsAlive: @escaping @Sendable (Int32) -> Bool,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.legacyReader = legacyReader
    self.paths = paths
    self.currentUserID = currentUserID
    self.processIsAlive = processIsAlive
    self.now = now
  }

  public static func live(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    Self(
      legacyReader: AutomationRuntimeStatusReader.live(environment: environment),
      paths: .live(environment: environment),
      currentUserID: Self.userID,
      processIsAlive: Self.isProcessAlive
    )
  }

  public func read(repository: RepositoryCoordinate) async -> AutomationRuntimeObservation {
    guard self.cutoverIsActive(repository: repository) else {
      return await self.legacyReader.read(repository: repository)
    }
    return self.readAutonomous(repository: repository)
  }

  private func cutoverIsActive(repository: RepositoryCoordinate) -> Bool {
    guard
      let handoff = self.strictObject(
        at: self.paths.handoffActivation,
        maximumBytes: Self.maximumActivationBytes
      ),
      Set(handoff.keys) == [
        "schema", "generation", "runtime_identity", "authority_directory", "service_entry",
      ],
      handoff["schema"] as? String == "productdev.activation.v1",
      let generation = handoff["generation"] as? String,
      let runtimeIdentity = handoff["runtime_identity"] as? String,
      Self.isLowercaseSHA(generation),
      runtimeIdentity == generation,
      handoff["authority_directory"] as? String == self.paths.authorityDirectory.path,
      handoff["service_entry"] as? String == self.paths.serviceEntry.path,
      let engine = self.strictObject(
        at: self.paths.engineActivation,
        maximumBytes: Self.maximumActivationBytes
      ),
      Set(engine.keys) == [
        "schema_version", "profile_id", "profile_digest", "authority_revision",
        "moment_repository", "moment_main_revision", "moment_handoff_contract_digest",
        "routing_mode", "productdev_launchagent_unloaded",
      ],
      engine["schema_version"] as? Int == 1,
      engine["profile_id"] as? String == "moments-autonomous-v2",
      engine["moment_repository"] as? String == repository.fullName,
      engine["routing_mode"] as? String == "recovery_first",
      engine["productdev_launchagent_unloaded"] as? Bool == true,
      engine["authority_revision"] as? String == generation,
      let momentRevision = engine["moment_main_revision"] as? String,
      Self.isLowercaseSHA(momentRevision),
      let profileDigest = engine["profile_digest"] as? String,
      Self.isSHA256Digest(profileDigest),
      let handoffDigest = engine["moment_handoff_contract_digest"] as? String,
      Self.isSHA256Digest(handoffDigest)
    else {
      return false
    }
    return true
  }

  private func readAutonomous(repository: RepositoryCoordinate) -> AutomationRuntimeObservation {
    guard FileManager.default.fileExists(atPath: self.paths.runtimeStatus.path) else {
      return .invalid("The activated ProductDev runtime status is unavailable.")
    }
    guard
      let data = try? self.readSecurely(
        self.paths.runtimeStatus,
        maximumBytes: Self.maximumRuntimeBytes
      )
    else {
      return .invalid("The activated ProductDev runtime status could not be read safely.")
    }
    do {
      let status = try Self.decodeAndValidateAutonomous(data, repository: repository)
      let age = self.now().timeIntervalSince(status.observedAt)
      guard age >= -30 else {
        return .invalid("The activated ProductDev runtime timestamp is in the future.")
      }
      if status.phase.isTerminal {
        return .autonomousTerminal(
          status,
          message: "Runtime outcome only; GitHub still proves merge and Issue completion."
        )
      }
      guard self.controllerIsLive() else {
        return .autonomousStale(
          status,
          message: "The activated ProductDev phase has no live controller process."
        )
      }
      return .autonomousLive(status)
    } catch ProductDevCutoverRuntimeError.repositoryConflict {
      return .invalid("The activated ProductDev runtime repository conflicts with this monitor.")
    } catch {
      return .invalid("The activated ProductDev runtime status is outside its public contract.")
    }
  }

  private func controllerIsLive() -> Bool {
    guard
      let data = try? self.readSecurely(
        self.paths.controllerPID,
        maximumBytes: 64,
        allowPublicRead: true
      ),
      let text = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      let pid = Int32(text), pid > 1
    else { return false }
    return self.processIsAlive(pid)
  }

  private func strictObject(at url: URL, maximumBytes: Int) -> [String: Any]? {
    guard let data = try? self.readSecurely(url, maximumBytes: maximumBytes),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return object
  }

  private func readSecurely(
    _ url: URL,
    maximumBytes: Int,
    allowPublicRead: Bool = false
  ) throws -> Data {
    let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw ProductDevCutoverRuntimeError.unreadable }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }

    var metadata = stat()
    guard Darwin.fstat(descriptor, &metadata) == 0,
      metadata.st_mode & S_IFMT == S_IFREG,
      metadata.st_uid == self.currentUserID,
      allowPublicRead
        ? metadata.st_mode & 0o022 == 0
        : metadata.st_mode & 0o077 == 0,
      metadata.st_size > 0,
      metadata.st_size <= maximumBytes,
      let data = try handle.read(upToCount: maximumBytes + 1),
      !data.isEmpty,
      data.count <= maximumBytes
    else {
      throw ProductDevCutoverRuntimeError.unreadable
    }
    return data
  }

  static func decodeAndValidateAutonomous(
    _ data: Data,
    repository: RepositoryCoordinate
  ) throws -> ProductDevAutonomousRuntimeStatus {
    guard data.count <= Self.maximumRuntimeBytes,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(object.keys) == [
        "schema_version", "profile_id", "repository", "issue_number", "phase", "role",
        "head_sha", "repair_attempt", "review_round", "observed_at",
      ],
      object["schema_version"] as? Int == 1,
      object["profile_id"] as? String == "moments-autonomous-v2",
      let observedRepository = object["repository"] as? String
    else {
      throw ProductDevCutoverRuntimeError.invalid
    }
    guard observedRepository.caseInsensitiveCompare(repository.fullName) == .orderedSame else {
      throw ProductDevCutoverRuntimeError.repositoryConflict
    }

    let issueNumber: Int?
    if object["issue_number"] is NSNull {
      issueNumber = nil
    } else if let value = object["issue_number"] as? Int, value > 0 {
      issueNumber = value
    } else {
      throw ProductDevCutoverRuntimeError.invalid
    }
    let headSHA: String?
    if object["head_sha"] is NSNull {
      headSHA = nil
    } else if let value = object["head_sha"] as? String, Self.isLowercaseSHA(value) {
      headSHA = value
    } else {
      throw ProductDevCutoverRuntimeError.invalid
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      guard let date = Self.parseDate(value) else {
        throw DecodingError.dataCorruptedError(
          in: try decoder.singleValueContainer(),
          debugDescription: "Runtime timestamp is not ISO 8601."
        )
      }
      return date
    }
    let status = try decoder.decode(ProductDevAutonomousRuntimeStatus.self, from: data)
    guard status.schemaVersion == 1,
      status.profileID == "moments-autonomous-v2",
      status.issueNumber == issueNumber,
      status.headSHA == headSHA,
      (0...3).contains(status.repairAttempt),
      status.reviewRound >= 0,
      status.role == Self.expectedRole(for: status.phase)
    else {
      throw ProductDevCutoverRuntimeError.invalid
    }
    return status
  }

  private static func expectedRole(
    for phase: ProductDevAutonomousRuntimePhase
  ) -> ProductDevAutonomousRuntimeRole {
    switch phase {
    case .implementing, .repairing: .implementer
    case .reviewing: .reviewer
    default: .controller
    }
  }

  private static func parseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    let whole = ISO8601DateFormatter()
    whole.formatOptions = [.withInternetDateTime]
    return whole.date(from: value)
  }

  private static func isLowercaseSHA(_ value: String) -> Bool {
    value.count == 40 && value.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
  }

  private static func isSHA256Digest(_ value: String) -> Bool {
    guard value.hasPrefix("sha256:") else { return false }
    let digest = value.dropFirst(7)
    return digest.count == 64
      && digest.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
  }

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

private enum ProductDevCutoverRuntimeError: Error {
  case invalid
  case repositoryConflict
  case unreadable
}
