import Foundation

public enum MonitorLane: String, CaseIterable, Codable, Sendable {
  case ready
  case waiting
  case queued
  case running
  case prChecks
  case blocked
  case completed

  public var title: String {
    switch self {
    case .ready: "Ready"
    case .waiting: "Waiting on dependencies"
    case .queued: "Runner queue"
    case .running: "Running"
    case .prChecks: "PR / Checks"
    case .blocked: "Blocked / Owner decision"
    case .completed: "Completed"
    }
  }

  public var sortOrder: Int {
    switch self {
    case .blocked: 0
    case .running: 1
    case .queued: 2
    case .prChecks: 3
    case .ready: 4
    case .waiting: 5
    case .completed: 6
    }
  }
}

public enum MonitorSeverity: String, Codable, Sendable {
  case normal
  case active
  case warning
  case success
}

public enum MonitorItemSource: String, Codable, Sendable {
  case issue
  case pullRequest
  case workflowRun
  case inferredState
}

public struct MonitorItem: Identifiable, Codable, Hashable, Sendable {
  public let id: String
  public let lane: MonitorLane
  public let source: MonitorItemSource
  public let title: String
  public let detail: String
  public let statusText: String?
  public let issueNumber: Int?
  public let pullRequestNumber: Int?
  public let workflowRunID: Int64?
  public let url: URL
  public let updatedAt: Date
  public let severity: MonitorSeverity
  public let priorityRank: Int
  public let sequenceNumber: Int

  public init(
    id: String,
    lane: MonitorLane,
    source: MonitorItemSource,
    title: String,
    detail: String,
    statusText: String? = nil,
    issueNumber: Int? = nil,
    pullRequestNumber: Int? = nil,
    workflowRunID: Int64? = nil,
    url: URL,
    updatedAt: Date,
    severity: MonitorSeverity = .normal,
    priorityRank: Int = 2,
    sequenceNumber: Int = .max
  ) {
    self.id = id
    self.lane = lane
    self.source = source
    self.title = title
    self.detail = detail
    self.statusText = statusText
    self.issueNumber = issueNumber
    self.pullRequestNumber = pullRequestNumber
    self.workflowRunID = workflowRunID
    self.url = url
    self.updatedAt = updatedAt
    self.severity = severity
    self.priorityRank = priorityRank
    self.sequenceNumber = sequenceNumber
  }
}

public enum MonitorHealth: String, Codable, Sendable {
  case idle
  case busy
  case attention
}

public struct ProjectProgress: Codable, Equatable, Sendable {
  public let completedCount: Int
  public let totalCount: Int

  public init(completedCount: Int, totalCount: Int) {
    let normalizedCompleted = max(0, completedCount)
    self.completedCount = normalizedCompleted
    self.totalCount = max(normalizedCompleted, totalCount)
  }

  public static let empty = Self(completedCount: 0, totalCount: 0)

  public var fractionCompleted: Double {
    guard self.totalCount > 0 else { return 0 }
    return Double(self.completedCount) / Double(self.totalCount)
  }

  public var percentage: Int {
    Int((self.fractionCompleted * 100).rounded())
  }

  public var isComplete: Bool {
    self.totalCount > 0 && self.completedCount == self.totalCount
  }
}

public struct MomentMonitorSnapshot: Codable, Equatable, Sendable {
  public let repository: RepositoryCoordinate
  public let generatedAt: Date
  public let items: [MonitorItem]
  public let projectProgress: ProjectProgress
  public let runtimeObservation: AutomationRuntimeObservation

  public init(
    repository: RepositoryCoordinate,
    generatedAt: Date,
    items: [MonitorItem],
    projectProgress: ProjectProgress = .empty,
    runtimeObservation: AutomationRuntimeObservation = .absent
  ) {
    self.repository = repository
    self.generatedAt = generatedAt
    self.items = items
    self.projectProgress = projectProgress
    self.runtimeObservation = runtimeObservation
  }

  public static func empty(repository: RepositoryCoordinate, at date: Date = Date()) -> Self {
    Self(repository: repository, generatedAt: date, items: [])
  }

  public func items(in lane: MonitorLane) -> [MonitorItem] {
    self.items.filter { $0.lane == lane }
  }

  public func replacingRuntimeObservation(
    _ observation: AutomationRuntimeObservation
  ) -> Self {
    Self(
      repository: self.repository,
      generatedAt: self.generatedAt,
      items: self.items,
      projectProgress: self.projectProgress,
      runtimeObservation: observation
    )
  }

  public var health: MonitorHealth {
    if [.invalid, .stale].contains(self.runtimeObservation.availability) {
      return .attention
    }
    if self.items.contains(where: { $0.lane == .blocked || $0.severity == .warning }) {
      return .attention
    }
    if self.items.contains(where: {
      $0.lane == .running || $0.lane == .queued || $0.lane == .prChecks
    }) || self.runtimeObservation.availability == .live {
      return .busy
    }
    return .idle
  }

  public var activeCount: Int {
    self.items.filter { [.queued, .running, .prChecks].contains($0.lane) }.count
  }
}

public struct MonitorConfiguration: Codable, Equatable, Sendable {
  public var repository: RepositoryCoordinate
  public var refreshIntervalSeconds: TimeInterval
  public var completedItemLimit: Int

  public init(
    repository: RepositoryCoordinate = .moment,
    refreshIntervalSeconds: TimeInterval = 30,
    completedItemLimit: Int = 8
  ) {
    self.repository = repository
    self.refreshIntervalSeconds = max(15, refreshIntervalSeconds)
    self.completedItemLimit = min(max(1, completedItemLimit), 30)
  }
}
