import Foundation

public enum AutomationRuntimeMode: String, Codable, Sendable {
  case implement
  case review
  case repair
  case unblock
}

public enum AutomationRuntimeOutcome: String, Codable, Sendable {
  case active
  case completed
  case blocked
  case failed
  case stopped
}

public enum AutomationRuntimeRole: String, Codable, Sendable {
  case controller
  case implementer
  case validator
  case reviewer
  case repairer
  case publisher
}

public enum AutomationRuntimeModel: String, Codable, Sendable {
  case luna = "gpt-5.6-luna"
  case sol = "gpt-5.6-sol"

  public var displayName: String {
    switch self {
    case .luna: "Luna"
    case .sol: "Sol"
    }
  }
}

public enum AutomationActivitySource: String, Codable, Sendable {
  case exec
  case appServer = "app_server"

  public var displayName: String {
    switch self {
    case .exec: "Codex Exec"
    case .appServer: "App Server"
    }
  }
}

public enum AutomationActivityKind: String, Codable, Sendable {
  case turn
  case command
  case fileChange = "file_change"
  case tool
  case plan
  case agent
}

public enum AutomationActivityState: String, Codable, Sendable {
  case started
  case completed
  case failed
}

public enum AutomationActivityAction: String, Codable, Sendable {
  case model
  case inspect
  case repository
  case test
  case build
  case format
  case package
  case command
  case fileChange = "file_change"
  case tool
  case plan
  case agent

  public var title: String {
    switch self {
    case .model: "Model turn"
    case .inspect: "Inspecting files"
    case .repository: "Checking repository"
    case .test: "Running tests"
    case .build: "Building project"
    case .format: "Formatting code"
    case .package: "Resolving packages"
    case .command: "Running command"
    case .fileChange: "Applying file changes"
    case .tool: "Using tool"
    case .plan: "Updating plan"
    case .agent: "Preparing response"
    }
  }

  public var resultTitle: String {
    switch self {
    case .model: "Model turn"
    case .inspect: "File inspection"
    case .repository: "Repository check"
    case .test: "Tests"
    case .build: "Build"
    case .format: "Formatting"
    case .package: "Package resolution"
    case .command: "Command"
    case .fileChange: "File changes"
    case .tool: "Tool call"
    case .plan: "Plan update"
    case .agent: "Response"
    }
  }
}

public struct AutomationActivityEvent: Codable, Equatable, Sendable {
  public let sequence: Int
  public let kind: AutomationActivityKind
  public let state: AutomationActivityState
  public let action: AutomationActivityAction
  public let observedAt: Date

  private enum CodingKeys: String, CodingKey {
    case sequence, kind, state, action
    case observedAt = "observed_at"
  }
}

public struct AutomationRuntimeActivity: Codable, Equatable, Sendable {
  public static let freshnessInterval: TimeInterval = 120
  public let schemaVersion: Int
  public let source: AutomationActivitySource
  public let sequence: Int
  public let kind: AutomationActivityKind
  public let state: AutomationActivityState
  public let action: AutomationActivityAction
  public let observedAt: Date
  public let completedCommands: Int
  public let failedCommands: Int
  public let completedFileChanges: Int
  public let completedTools: Int
  public let recent: [AutomationActivityEvent]

  public var title: String {
    switch self.state {
    case .started: self.action.title
    case .completed: "\(self.action.resultTitle) completed"
    case .failed: "\(self.action.resultTitle) failed"
    }
  }

  public func isRecent(at now: Date, maximumAge: TimeInterval = Self.freshnessInterval) -> Bool {
    let age = now.timeIntervalSince(self.observedAt)
    return age >= 0 && age <= maximumAge
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case source, sequence, kind, state, action
    case observedAt = "observed_at"
    case completedCommands = "completed_commands"
    case failedCommands = "failed_commands"
    case completedFileChanges = "completed_file_changes"
    case completedTools = "completed_tools"
    case recent
  }
}

public struct AutomationIssueDuration: Codable, Equatable, Sendable {
  public let issueNumber: Int
  public let durationMilliseconds: Int64

  public init(issueNumber: Int, durationMilliseconds: Int64) {
    self.issueNumber = issueNumber
    self.durationMilliseconds = durationMilliseconds
  }

  private enum CodingKeys: String, CodingKey {
    case issueNumber = "issue_number"
    case durationMilliseconds = "duration_ms"
  }
}

public enum AutomationRuntimeStage: Int, CaseIterable, Codable, Sendable {
  case prepare
  case develop
  case validate
  case review
  case publish

  public var title: String {
    switch self {
    case .prepare: "Prepare"
    case .develop: "Develop"
    case .validate: "Validate"
    case .review: "Review"
    case .publish: "Publish"
    }
  }
}

public enum AutomationLifecycleStage: Int, CaseIterable, Codable, Sendable {
  case implementing
  case checking
  case reviewing
  case publishing
  case merging
  case completed

  public var title: String {
    switch self {
    case .implementing: "Implement"
    case .checking: "Check"
    case .reviewing: "Review"
    case .publishing: "Publish"
    case .merging: "Merge"
    case .completed: "Done"
    }
  }
}

public enum AutomationRuntimePhase: String, Codable, CaseIterable, Sendable {
  case preparingWorkspace = "preparing_workspace"
  case adoptingExistingPR = "adopting_existing_pr"
  case lunaImplementation = "luna_implementation"
  case solCIRepair = "sol_ci_repair"
  case solHighUnblock = "sol_high_unblock"
  case committingCandidate = "committing_candidate"
  case prFast = "pr_fast"
  case solPRFastRepair = "sol_pr_fast_repair"
  case solReview = "sol_review"
  case solReviewRepair = "sol_review_repair"
  case lunaVerification = "luna_verification"
  case publishingBranch = "publishing_branch"
  case creatingPR = "creating_pr"
  case verifyingExactHead = "verifying_exact_head"
  case mergingPR = "merging_pr"
  case closingIssue = "closing_issue"
  case completed
  case blocked
  case failed
  case stoppedNoChange = "stopped_no_change"

  public var title: String {
    switch self {
    case .preparingWorkspace: "Preparing workspace"
    case .adoptingExistingPR: "Adopting existing PR"
    case .lunaImplementation: "Luna development"
    case .solCIRepair: "Sol CI repair"
    case .solHighUnblock: "Sol High unblock"
    case .committingCandidate: "Committing candidate"
    case .prFast: "PR Fast validation"
    case .solPRFastRepair: "Sol PR Fast repair"
    case .solReview: "Sol review"
    case .solReviewRepair: "Sol review repair"
    case .lunaVerification: "Luna verification"
    case .publishingBranch: "Publishing branch"
    case .creatingPR: "Creating pull request"
    case .verifyingExactHead: "Verifying exact head"
    case .mergingPR: "Merging pull request"
    case .closingIssue: "Closing originating Issue"
    case .completed: "Completed"
    case .blocked: "Blocked"
    case .failed: "Failed"
    case .stoppedNoChange: "Stopped without a patch"
    }
  }

  public var stage: AutomationRuntimeStage {
    switch self {
    case .preparingWorkspace, .adoptingExistingPR:
      .prepare
    case .lunaImplementation, .solCIRepair, .solHighUnblock, .committingCandidate:
      .develop
    case .prFast, .solPRFastRepair:
      .validate
    case .solReview, .solReviewRepair, .lunaVerification:
      .review
    case .publishingBranch, .creatingPR, .verifyingExactHead, .mergingPR, .closingIssue,
      .completed, .blocked, .failed, .stoppedNoChange:
      .publish
    }
  }

  public var lifecycleStage: AutomationLifecycleStage {
    switch self {
    case .preparingWorkspace, .adoptingExistingPR, .lunaImplementation, .solCIRepair,
      .solHighUnblock, .committingCandidate:
      .implementing
    case .prFast, .solPRFastRepair:
      .checking
    case .solReview, .solReviewRepair, .lunaVerification:
      .reviewing
    case .publishingBranch, .creatingPR, .verifyingExactHead:
      .publishing
    case .mergingPR, .closingIssue:
      .merging
    case .completed, .blocked, .failed, .stoppedNoChange:
      .completed
    }
  }

  public var isTerminal: Bool {
    switch self {
    case .completed, .blocked, .failed, .stoppedNoChange: true
    default: false
    }
  }
}

public struct AutomationRuntimeStatus: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let formatVersion: String
  public let repository: String
  public let runID: String
  public let issueNumber: Int
  public let pullRequestNumber: Int?
  public let mode: AutomationRuntimeMode
  public let phase: AutomationRuntimePhase
  public let lastActivePhase: AutomationRuntimePhase?
  public let outcome: AutomationRuntimeOutcome
  public let model: AutomationRuntimeModel?
  public let role: AutomationRuntimeRole?
  public let roundNumber: Int?
  public let totalRounds: Int?
  public let repairAttempt: Int?
  public let runnerPID: Int32
  public let sequence: Int
  public let startedAt: Date
  public let phaseStartedAt: Date
  public let updatedAt: Date
  public let baseSHA: String?
  public let headSHA: String?
  public let activity: AutomationRuntimeActivity?
  public let issueDurations: [AutomationIssueDuration]?

  public init(
    schemaVersion: Int = 1,
    formatVersion: String = "moment.automation-runtime.v1",
    repository: String,
    runID: String,
    issueNumber: Int,
    pullRequestNumber: Int? = nil,
    mode: AutomationRuntimeMode,
    phase: AutomationRuntimePhase,
    lastActivePhase: AutomationRuntimePhase? = nil,
    outcome: AutomationRuntimeOutcome = .active,
    model: AutomationRuntimeModel? = nil,
    role: AutomationRuntimeRole? = nil,
    roundNumber: Int? = nil,
    totalRounds: Int? = nil,
    repairAttempt: Int? = nil,
    runnerPID: Int32,
    sequence: Int,
    startedAt: Date,
    phaseStartedAt: Date,
    updatedAt: Date,
    baseSHA: String? = nil,
    headSHA: String? = nil,
    activity: AutomationRuntimeActivity? = nil,
    issueDurations: [AutomationIssueDuration]? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.formatVersion = formatVersion
    self.repository = repository
    self.runID = runID
    self.issueNumber = issueNumber
    self.pullRequestNumber = pullRequestNumber
    self.mode = mode
    self.phase = phase
    self.lastActivePhase = lastActivePhase
    self.outcome = outcome
    self.model = model
    self.role = role
    self.roundNumber = roundNumber
    self.totalRounds = totalRounds
    self.repairAttempt = repairAttempt
    self.runnerPID = runnerPID
    self.sequence = sequence
    self.startedAt = startedAt
    self.phaseStartedAt = phaseStartedAt
    self.updatedAt = updatedAt
    self.baseSHA = baseSHA
    self.headSHA = headSHA
    self.activity = activity
    self.issueDurations = issueDurations
  }

  public func recordedDurationMilliseconds(for issueNumber: Int) -> Int64? {
    self.issueDurations?.first(where: { $0.issueNumber == issueNumber })?.durationMilliseconds
  }

  public func observedDurationMilliseconds(
    for issueNumber: Int,
    at now: Date,
    runnerIsLive: Bool
  ) -> Int64? {
    guard let recorded = self.recordedDurationMilliseconds(for: issueNumber) else {
      return nil
    }
    guard runnerIsLive, issueNumber == self.issueNumber else { return recorded }
    let liveMilliseconds = Int64(max(0, now.timeIntervalSince(self.updatedAt)) * 1000)
    return min(315_360_000_000, recorded + liveMilliseconds)
  }

  public var phaseDetail: String? {
    if let roundNumber, let totalRounds {
      return "round \(roundNumber) of \(totalRounds)"
    }
    if let repairAttempt {
      return "repair attempt \(repairAttempt)"
    }
    return nil
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case formatVersion = "format_version"
    case repository
    case runID = "run_id"
    case issueNumber = "issue_number"
    case pullRequestNumber = "pull_request_number"
    case mode
    case phase
    case lastActivePhase = "last_active_phase"
    case outcome
    case model
    case role
    case roundNumber = "round_number"
    case totalRounds = "total_rounds"
    case repairAttempt = "repair_attempt"
    case runnerPID = "runner_pid"
    case sequence
    case startedAt = "started_at"
    case phaseStartedAt = "phase_started_at"
    case updatedAt = "updated_at"
    case baseSHA = "base_sha"
    case headSHA = "head_sha"
    case activity
    case issueDurations = "issue_durations"
  }
}

public enum AutomationRuntimeAvailability: String, Codable, Sendable {
  case absent
  case live
  case terminal
  case stale
  case invalid
}

public struct AutomationRuntimeObservation: Codable, Equatable, Sendable {
  public let availability: AutomationRuntimeAvailability
  public let status: AutomationRuntimeStatus?
  public let message: String?

  public init(
    availability: AutomationRuntimeAvailability,
    status: AutomationRuntimeStatus? = nil,
    message: String? = nil
  ) {
    self.availability = availability
    self.status = status
    self.message = message
  }

  public static let absent = Self(availability: .absent)

  public static func live(_ status: AutomationRuntimeStatus) -> Self {
    Self(availability: .live, status: status)
  }

  public static func terminal(_ status: AutomationRuntimeStatus, message: String? = nil) -> Self {
    Self(availability: .terminal, status: status, message: message)
  }

  public static func stale(_ status: AutomationRuntimeStatus, message: String) -> Self {
    Self(availability: .stale, status: status, message: message)
  }

  public static func invalid(_ message: String) -> Self {
    Self(availability: .invalid, message: message)
  }
}
