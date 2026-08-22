import Foundation

public struct MobileDashboardEnvelope: Codable, Equatable, Sendable {
  public static let schemaVersion = 1

  public let schemaVersion: Int
  public let repository: String
  public let generatedAt: Date
  public let servedAt: Date
  public let health: MonitorHealth
  public let projectProgress: ProjectProgress
  public let runtime: MobileRuntimeSummary
  public let lanes: [MobileDashboardLane]

  public init(snapshot: MomentMonitorSnapshot, servedAt: Date = Date()) {
    self.schemaVersion = Self.schemaVersion
    self.repository = snapshot.repository.fullName
    self.generatedAt = snapshot.generatedAt
    self.servedAt = servedAt
    self.health = snapshot.health
    self.projectProgress = snapshot.projectProgress
    self.runtime = MobileRuntimeSummary(observation: snapshot.runtimeObservation)
    self.lanes = MonitorLane.allCases
      .sorted { $0.sortOrder < $1.sortOrder }
      .compactMap { lane in
        let items = snapshot.items(in: lane)
        guard !items.isEmpty else { return nil }
        return MobileDashboardLane(
          lane: lane,
          title: lane.title,
          items: items.map(MobileDashboardItem.init)
        )
      }
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
  public let startedAt: Date?
  public let phaseStartedAt: Date?
  public let updatedAt: Date?

  public init(observation: AutomationRuntimeObservation) {
    let status = observation.status
    let effectivePhase = status?.lastActivePhase ?? status?.phase
    self.availability = observation.availability
    self.message = observation.message
    self.phase = status?.phase
    self.phaseTitle = status?.phase.title
    self.activeStage = effectivePhase?.stage
    self.lastActivePhase = status?.lastActivePhase
    self.lastActivePhaseTitle = status?.lastActivePhase?.title
    self.outcome = status?.outcome
    self.model = status?.model
    self.role = status?.role
    self.issueNumber = status?.issueNumber
    self.pullRequestNumber = status?.pullRequestNumber
    self.roundNumber = status?.roundNumber
    self.totalRounds = status?.totalRounds
    self.repairAttempt = status?.repairAttempt
    self.startedAt = status?.startedAt
    self.phaseStartedAt = status?.phaseStartedAt
    self.updatedAt = status?.updatedAt
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
  public let severity: MonitorSeverity

  public init(item: MonitorItem) {
    self.lane = item.lane
    self.title = item.title
    self.detail = item.detail
    self.statusText = item.statusText
    self.issueNumber = item.issueNumber
    self.pullRequestNumber = item.pullRequestNumber
    self.url = item.url
    self.updatedAt = item.updatedAt
    self.severity = item.severity
  }
}

public final class MobileDashboardSnapshotStore: @unchecked Sendable {
  private let lock = NSLock()
  private var snapshot: MomentMonitorSnapshot

  public init(snapshot: MomentMonitorSnapshot) {
    self.snapshot = snapshot
  }

  public func update(_ snapshot: MomentMonitorSnapshot) {
    self.lock.withLock {
      self.snapshot = snapshot
    }
  }

  public func encodedSnapshot(servedAt: Date = Date()) throws -> Data {
    let snapshot = self.lock.withLock { self.snapshot }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(MobileDashboardEnvelope(snapshot: snapshot, servedAt: servedAt))
  }
}
