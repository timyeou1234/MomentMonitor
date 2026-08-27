import Foundation

public struct MobileDashboardEnvelope: Codable, Equatable, Sendable {
  public static let schemaVersion = 6

  public let schemaVersion: Int
  public let repository: String
  public let generatedAt: Date
  public let servedAt: Date
  public let health: MonitorHealth
  public let projectProgress: ProjectProgress
  public let codexUsage: MobileCodexUsageSummary
  public let oxAudit: MobileOxAuditSummary
  public let runtime: MobileRuntimeSummary
  public let lanes: [MobileDashboardLane]

  public init(
    snapshot: MomentMonitorSnapshot,
    codexUsage: CodexUsageObservation,
    oxAudit: OxAuditObservation = .absent,
    servedAt: Date = Date()
  ) {
    self.schemaVersion = Self.schemaVersion
    self.repository = snapshot.repository.fullName
    self.generatedAt = snapshot.generatedAt
    self.servedAt = servedAt
    self.health = snapshot.health
    self.projectProgress = snapshot.projectProgress
    self.codexUsage = MobileCodexUsageSummary(observation: codexUsage, now: servedAt)
    self.oxAudit = MobileOxAuditSummary(observation: oxAudit)
    self.runtime = MobileRuntimeSummary(observation: snapshot.runtimeObservation, now: servedAt)
    self.lanes = MonitorLane.allCases
      .sorted { $0.sortOrder < $1.sortOrder }
      .compactMap { lane in
        let items = snapshot.items(in: lane)
        guard !items.isEmpty else { return nil }
        return MobileDashboardLane(
          lane: lane,
          title: lane.title,
          items: items.map {
            MobileDashboardItem(
              item: $0,
              runtimeObservation: snapshot.runtimeObservation,
              servedAt: servedAt
            )
          }
        )
      }
  }
}

public struct MobileOxAuditSummary: Codable, Equatable, Sendable {
  public let availability: OxAuditAvailability
  public let state: OxAuditState?
  public let model: String?
  public let issueNumber: Int?
  public let completedCount: Int?
  public let totalCount: Int?
  public let lastHTTPStatus: Int?
  public let updatedAt: Date?
  public let nextAttemptAt: Date?
  public let message: String?

  public init(observation: OxAuditObservation) {
    self.availability = observation.availability
    self.state = observation.status?.state
    self.model = observation.status?.model
    self.issueNumber = observation.status?.currentIssue
    self.completedCount = observation.status?.completedCount
    self.totalCount = observation.status?.totalCount
    self.lastHTTPStatus = observation.status?.lastHTTPStatus
    self.updatedAt = observation.status?.updatedAt
    self.nextAttemptAt = observation.status?.nextAttemptAt
    self.message = observation.message
  }
}

public struct MobileCodexUsageSummary: Codable, Equatable, Sendable {
  public let availability: CodexUsageAvailability
  public let primary: CodexUsageWindow?
  public let secondary: CodexUsageWindow?
  public let fetchedAt: Date?
  public let message: String?

  public init(observation: CodexUsageObservation, now: Date = Date()) {
    let current = observation.enforcingFreshness(at: now)
    self.availability = current.availability
    self.primary = current.primary
    self.secondary = current.secondary
    self.fetchedAt = current.fetchedAt
    self.message = current.message
  }
}

public struct MobileRuntimeSummary: Codable, Equatable, Sendable {
  public let availability: AutomationRuntimeAvailability
  public let message: String?
  public let phase: AutomationRuntimePhase?
  public let phaseTitle: String?
  public let activeStage: AutomationRuntimeStage?
  public let lastActivePhase: AutomationRuntimePhase?
  public let lastActivePhaseTitle: String?
  public let outcome: AutomationRuntimeOutcome?
  public let model: AutomationRuntimeModel?
  public let role: AutomationRuntimeRole?
  public let issueNumber: Int?
  public let pullRequestNumber: Int?
  public let roundNumber: Int?
  public let totalRounds: Int?
  public let repairAttempt: Int?
  public let strategy: AutomationStrategyProgress?
  public let activity: AutomationRuntimeActivity?
  public let startedAt: Date?
  public let phaseStartedAt: Date?
  public let updatedAt: Date?
  public let issueDurationMilliseconds: Int64?
  public let source: String
  public let autonomousPhase: ProductDevAutonomousRuntimePhase?
  public let autonomousRole: ProductDevAutonomousRuntimeRole?

  public init(observation: AutomationRuntimeObservation, now: Date = Date()) {
    let status = observation.status
    let autonomous = observation.autonomousStatus
    let effectivePhase = status?.lastActivePhase ?? status?.phase
    self.availability = observation.availability
    self.message = observation.message
    self.phase = status?.phase
    self.phaseTitle = autonomous?.phase.title ?? status?.phase.title
    self.activeStage = autonomous?.phase.stage ?? effectivePhase?.stage
    self.lastActivePhase = status?.lastActivePhase
    self.lastActivePhaseTitle = status?.lastActivePhase?.title
    self.outcome = status?.outcome
    self.model = status?.model
    self.role = status?.role
    self.issueNumber = autonomous?.issueNumber ?? status?.issueNumber
    self.pullRequestNumber = status?.pullRequestNumber
    self.roundNumber =
      autonomous.flatMap { $0.reviewRound > 0 ? $0.reviewRound : nil }
      ?? status?.roundNumber
    self.totalRounds = status?.totalRounds
    self.repairAttempt =
      autonomous.flatMap { $0.repairAttempt > 0 ? $0.repairAttempt : nil }
      ?? status?.repairAttempt
    self.strategy = AutomationStrategyProgress(observation: observation)
    self.activity =
      observation.availability == .live
        && status?.activity?.isRecent(at: now) == true ? status?.activity : nil
    self.startedAt = status?.startedAt
    self.phaseStartedAt = status?.phaseStartedAt
    self.updatedAt = autonomous?.observedAt ?? status?.updatedAt
    self.issueDurationMilliseconds = status?.observedDurationMilliseconds(
      for: status?.issueNumber ?? 0,
      at: now,
      runnerIsLive: observation.availability == .live
    )
    self.source = autonomous == nil ? "moment" : "productdev"
    self.autonomousPhase = autonomous?.phase
    self.autonomousRole = autonomous?.role
  }
}

public struct MobileDashboardLane: Codable, Equatable, Sendable {
  public let lane: MonitorLane
  public let title: String
  public let items: [MobileDashboardItem]

  public init(lane: MonitorLane, title: String, items: [MobileDashboardItem]) {
    self.lane = lane
    self.title = title
    self.items = items
  }
}

public struct MobileDashboardItem: Codable, Equatable, Sendable {
  public let lane: MonitorLane
  public let title: String
  public let detail: String
  public let statusText: String?
  public let issueNumber: Int?
  public let pullRequestNumber: Int?
  public let url: URL
  public let updatedAt: Date
  public let automationDurationMilliseconds: Int64?
  public let severity: MonitorSeverity

  public init(
    item: MonitorItem,
    runtimeObservation: AutomationRuntimeObservation = .absent,
    servedAt: Date = Date()
  ) {
    self.lane = item.lane
    self.title = item.title
    self.detail = item.detail
    self.statusText = item.statusText
    self.issueNumber = item.issueNumber
    self.pullRequestNumber = item.pullRequestNumber
    self.url = item.url
    self.updatedAt = item.updatedAt
    if let issueNumber = item.issueNumber,
      let status = runtimeObservation.status,
      let duration = status.observedDurationMilliseconds(
        for: issueNumber,
        at: servedAt,
        runnerIsLive: runtimeObservation.availability == .live
      )
    {
      self.automationDurationMilliseconds = duration
    } else {
      self.automationDurationMilliseconds = item.automationDurationMilliseconds
    }
    self.severity = item.severity
  }
}

public final class MobileDashboardSnapshotStore: @unchecked Sendable {
  private let lock = NSLock()
  private var snapshot: MomentMonitorSnapshot
  private var codexUsage: CodexUsageObservation
  private var oxAudit: OxAuditObservation

  public init(
    snapshot: MomentMonitorSnapshot,
    codexUsage: CodexUsageObservation = .unavailable(message: "Not refreshed yet."),
    oxAudit: OxAuditObservation = .absent
  ) {
    self.snapshot = snapshot
    self.codexUsage = codexUsage
    self.oxAudit = oxAudit
  }

  public func update(_ snapshot: MomentMonitorSnapshot) {
    self.lock.withLock {
      self.snapshot = snapshot
    }
  }

  public func updateCodexUsage(_ codexUsage: CodexUsageObservation) {
    self.lock.withLock {
      self.codexUsage = codexUsage
    }
  }

  public func updateOxAudit(_ oxAudit: OxAuditObservation) {
    self.lock.withLock {
      self.oxAudit = oxAudit
    }
  }

  public func encodedSnapshot(servedAt: Date = Date()) throws -> Data {
    let values = self.lock.withLock { (self.snapshot, self.codexUsage, self.oxAudit) }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(
      MobileDashboardEnvelope(
        snapshot: values.0,
        codexUsage: values.1,
        oxAudit: values.2,
        servedAt: servedAt
      ))
  }
}
