import CryptoKit
import Foundation

public enum DevelopmentObservationClassification: String, Codable, CaseIterable, Sendable {
  case healthy
  case watch
  case blockedTechnical = "blocked_technical"
  case needsOwner = "needs_owner"
  case stale

  public var title: String {
    switch self {
    case .healthy: "Healthy"
    case .watch: "Watch"
    case .blockedTechnical: "Technical block"
    case .needsOwner: "Owner decision"
    case .stale: "Stale state"
    }
  }
}

public enum DevelopmentObservationRecommendation: String, Codable, CaseIterable, Sendable {
  case none
  case keepWatching = "keep_watching"
  case notifyOwner = "notify_owner"
  case recommendCodexDiagnosis = "recommend_codex_diagnosis"

  public var title: String {
    switch self {
    case .none: "No action"
    case .keepWatching: "Keep watching"
    case .notifyOwner: "Notify owner"
    case .recommendCodexDiagnosis: "Recommend Codex diagnosis"
    }
  }
}

public enum DevelopmentDiagnosisSource: String, Codable, Sendable {
  case deterministic
  case omlx
}

public struct DevelopmentDiagnosis: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let fingerprint: String
  public let classification: DevelopmentObservationClassification
  public let recommendation: DevelopmentObservationRecommendation
  public let issueNumber: Int?
  public let summary: String
  public let source: DevelopmentDiagnosisSource
  public let generatedAt: Date

  public init(
    fingerprint: String,
    classification: DevelopmentObservationClassification,
    recommendation: DevelopmentObservationRecommendation,
    issueNumber: Int?,
    summary: String,
    source: DevelopmentDiagnosisSource,
    generatedAt: Date
  ) {
    self.schemaVersion = 1
    self.fingerprint = fingerprint
    self.classification = classification
    self.recommendation = recommendation
    self.issueNumber = issueNumber
    self.summary = summary
    self.source = source
    self.generatedAt = generatedAt
  }
}

public enum DevelopmentObservedItemState: String, Codable, CaseIterable, Sendable {
  case ready
  case waiting
  case queued
  case running
  case prChecks = "pr_checks"
  case blocked
  case autoRecovery = "auto_recovery"
  case ownerDecision = "owner_decision"
  case completed
}

public struct DevelopmentObservedItem: Codable, Equatable, Sendable {
  public let issueNumber: Int
  public let pullRequestNumber: Int?
  public let state: DevelopmentObservedItemState
  public let severity: MonitorSeverity

  public init(
    issueNumber: Int,
    pullRequestNumber: Int?,
    state: DevelopmentObservedItemState,
    severity: MonitorSeverity
  ) {
    self.issueNumber = issueNumber
    self.pullRequestNumber = pullRequestNumber
    self.state = state
    self.severity = severity
  }
}

public struct DevelopmentObservedRuntime: Codable, Equatable, Sendable {
  public let availability: AutomationRuntimeAvailability
  public let issueNumber: Int?
  public let pullRequestNumber: Int?
  public let phase: AutomationRuntimePhase?
  public let outcome: AutomationRuntimeOutcome?
  public let model: AutomationRuntimeModel?
  public let role: AutomationRuntimeRole?
  public let roundNumber: Int?
  public let totalRounds: Int?
  public let repairAttempt: Int?
  public let autonomousPhase: ProductDevAutonomousRuntimePhase?
  public let autonomousRole: ProductDevAutonomousRuntimeRole?

  public init(observation: AutomationRuntimeObservation) {
    self.availability = observation.availability
    self.issueNumber = observation.issueNumber
    self.pullRequestNumber = observation.status?.pullRequestNumber
    self.phase = observation.status?.phase
    self.outcome = observation.status?.outcome
    self.model = observation.status?.model
    self.role = observation.status?.role
    self.roundNumber = observation.status?.roundNumber
    self.totalRounds = observation.status?.totalRounds
    self.repairAttempt = observation.status?.repairAttempt
    self.autonomousPhase = observation.autonomousStatus?.phase
    self.autonomousRole = observation.autonomousStatus?.role
  }
}

public struct DevelopmentObservationPayload: Codable, Equatable, Sendable {
  public static let maximumItems = 64

  public let schemaVersion: Int
  public let repository: String
  public let runtime: DevelopmentObservedRuntime
  public let items: [DevelopmentObservedItem]

  public init(snapshot: MomentMonitorSnapshot) {
    self.schemaVersion = 1
    self.repository = snapshot.repository.fullName
    self.runtime = DevelopmentObservedRuntime(observation: snapshot.runtimeObservation)
    self.items = snapshot.items
      .compactMap(Self.observedItem)
      .sorted(by: Self.itemComesBefore)
      .prefix(Self.maximumItems)
      .map { $0 }
  }

  public var fingerprint: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(self) else { return "invalid" }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func observedItem(_ item: MonitorItem) -> DevelopmentObservedItem? {
    guard let issueNumber = item.issueNumber else { return nil }
    let state: DevelopmentObservedItemState
    if item.lane == .blocked, item.statusText == "owner decision" {
      state = .ownerDecision
    } else if item.lane == .blocked, item.statusText == "auto recovery" {
      state = .autoRecovery
    } else {
      switch item.lane {
      case .ready: state = .ready
      case .waiting: state = .waiting
      case .queued: state = .queued
      case .running: state = .running
      case .prChecks: state = .prChecks
      case .blocked: state = .blocked
      case .completed: state = .completed
      }
    }
    return DevelopmentObservedItem(
      issueNumber: issueNumber,
      pullRequestNumber: item.pullRequestNumber,
      state: state,
      severity: item.severity
    )
  }

  private static func itemComesBefore(
    _ lhs: DevelopmentObservedItem,
    _ rhs: DevelopmentObservedItem
  ) -> Bool {
    let lhsRank = Self.stateRank(lhs.state)
    let rhsRank = Self.stateRank(rhs.state)
    if lhsRank != rhsRank { return lhsRank < rhsRank }
    if lhs.issueNumber != rhs.issueNumber { return lhs.issueNumber < rhs.issueNumber }
    return (lhs.pullRequestNumber ?? 0) < (rhs.pullRequestNumber ?? 0)
  }

  private static func stateRank(_ state: DevelopmentObservedItemState) -> Int {
    switch state {
    case .ownerDecision: 0
    case .blocked: 1
    case .autoRecovery: 2
    case .running: 3
    case .queued: 4
    case .prChecks: 5
    case .ready: 6
    case .waiting: 7
    case .completed: 8
    }
  }
}

public struct DevelopmentObservationAssessment: Equatable, Sendable {
  public let payload: DevelopmentObservationPayload
  public let classification: DevelopmentObservationClassification
  public let recommendation: DevelopmentObservationRecommendation
  public let issueNumber: Int?
  public let fallbackSummary: String

  public init(snapshot: MomentMonitorSnapshot) {
    let payload = DevelopmentObservationPayload(snapshot: snapshot)
    self.payload = payload

    if let item = payload.items.first(where: { $0.state == .ownerDecision }) {
      self.classification = .needsOwner
      self.recommendation = .notifyOwner
      self.issueNumber = item.issueNumber
      self.fallbackSummary =
        "Issue #\(item.issueNumber) needs a bounded Owner decision. Automation remains read-only here."
    } else if [.invalid, .stale].contains(payload.runtime.availability) {
      self.classification = .stale
      self.recommendation = .notifyOwner
      self.issueNumber = payload.runtime.issueNumber
      self.fallbackSummary =
        "Local controller telemetry is stale or invalid. GitHub remains authoritative."
    } else if let item = payload.items.first(where: { $0.state == .blocked }) {
      self.classification = .blockedTechnical
      self.recommendation = .recommendCodexDiagnosis
      self.issueNumber = item.issueNumber
      self.fallbackSummary =
        "Issue #\(item.issueNumber) has a technical block without an observed automatic recovery route."
    } else if let item = payload.items.first(where: { $0.state == .autoRecovery }) {
      self.classification = .blockedTechnical
      self.recommendation = .keepWatching
      self.issueNumber = item.issueNumber
      self.fallbackSummary =
        "Issue #\(item.issueNumber) is blocked, and its existing Codex recovery authorization remains authoritative."
    } else if let item = payload.items.first(where: { $0.severity == .warning }) {
      self.classification = .watch
      self.recommendation = .keepWatching
      self.issueNumber = item.issueNumber
      self.fallbackSummary =
        "Issue #\(item.issueNumber) has a warning state that should be watched."
    } else if payload.runtime.availability == .live
      || payload.items.contains(where: { [.running, .queued, .prChecks].contains($0.state) })
    {
      self.classification = .healthy
      self.recommendation = .keepWatching
      self.issueNumber = payload.runtime.issueNumber
      self.fallbackSummary =
        "Development is active and no observer-level intervention is indicated."
    } else {
      self.classification = .healthy
      self.recommendation = .none
      self.issueNumber = nil
      self.fallbackSummary = "No active development problem is visible."
    }
  }

  public func deterministicDiagnosis(at date: Date) -> DevelopmentDiagnosis {
    DevelopmentDiagnosis(
      fingerprint: self.payload.fingerprint,
      classification: self.classification,
      recommendation: self.recommendation,
      issueNumber: self.issueNumber,
      summary: self.fallbackSummary,
      source: .deterministic,
      generatedAt: date
    )
  }
}

public struct DevelopmentModelDiagnosis: Equatable, Sendable {
  public let classification: DevelopmentObservationClassification
  public let recommendation: DevelopmentObservationRecommendation
  public let summary: String

  public init(
    classification: DevelopmentObservationClassification,
    recommendation: DevelopmentObservationRecommendation,
    summary: String
  ) {
    self.classification = classification
    self.recommendation = recommendation
    self.summary = summary
  }
}

public protocol DevelopmentObserverModelCalling: Sendable {
  func diagnose(assessment: DevelopmentObservationAssessment) async throws
    -> DevelopmentModelDiagnosis
}

public actor DevelopmentObserver {
  public static let defaultRetryInterval: TimeInterval = 300

  private struct Cache: Sendable {
    let fingerprint: String
    let localModelEnabled: Bool
    let diagnosis: DevelopmentDiagnosis
    let attemptedAt: Date
  }

  private let modelClient: (any DevelopmentObserverModelCalling)?
  private let retryInterval: TimeInterval
  private var cache: Cache?

  public init(
    modelClient: (any DevelopmentObserverModelCalling)? = nil,
    retryInterval: TimeInterval = DevelopmentObserver.defaultRetryInterval
  ) {
    self.modelClient = modelClient
    self.retryInterval = max(15, retryInterval)
  }

  public static func live() -> DevelopmentObserver {
    DevelopmentObserver(modelClient: try? OMLXDevelopmentObserverClient.live())
  }

  public func observe(
    snapshot: MomentMonitorSnapshot,
    localModelEnabled: Bool,
    at date: Date = Date()
  ) async -> DevelopmentDiagnosis {
    let assessment = DevelopmentObservationAssessment(snapshot: snapshot)
    let fingerprint = assessment.payload.fingerprint

    if let cache, cache.fingerprint == fingerprint,
      cache.localModelEnabled == localModelEnabled
    {
      if cache.diagnosis.source == .omlx
        || !localModelEnabled
        || date.timeIntervalSince(cache.attemptedAt) < self.retryInterval
      {
        return cache.diagnosis
      }
    }

    let fallback = assessment.deterministicDiagnosis(at: date)
    guard localModelEnabled, let modelClient = self.modelClient else {
      self.cache = Cache(
        fingerprint: fingerprint,
        localModelEnabled: localModelEnabled,
        diagnosis: fallback,
        attemptedAt: date
      )
      return fallback
    }

    let diagnosis: DevelopmentDiagnosis
    do {
      let modelResult = try await modelClient.diagnose(assessment: assessment)
      guard modelResult.classification == assessment.classification,
        modelResult.recommendation == assessment.recommendation
      else { throw DevelopmentObserverError.policyMismatch }
      diagnosis = DevelopmentDiagnosis(
        fingerprint: fingerprint,
        classification: assessment.classification,
        recommendation: assessment.recommendation,
        issueNumber: assessment.issueNumber,
        summary: modelResult.summary,
        source: .omlx,
        generatedAt: date
      )
    } catch is CancellationError {
      return fallback
    } catch {
      diagnosis = fallback
    }

    self.cache = Cache(
      fingerprint: fingerprint,
      localModelEnabled: localModelEnabled,
      diagnosis: diagnosis,
      attemptedAt: date
    )
    return diagnosis
  }
}

public enum DevelopmentObserverError: LocalizedError, Equatable, Sendable {
  case invalidEndpoint
  case unavailable
  case timedOut
  case invalidResponse
  case responseTooLarge
  case policyMismatch

  public var errorDescription: String? {
    switch self {
    case .invalidEndpoint: "The local observer endpoint is not a permitted loopback URL."
    case .unavailable: "The local observer model is unavailable."
    case .timedOut: "The local observer model did not respond in time."
    case .invalidResponse: "The local observer model returned an invalid response."
    case .responseTooLarge: "The local observer model response exceeded its bound."
    case .policyMismatch: "The local observer model attempted to change the deterministic decision."
    }
  }
}
