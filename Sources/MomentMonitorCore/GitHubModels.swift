import Foundation

public struct GitHubLabel: Codable, Hashable, Sendable {
  public let name: String
  public let color: String?

  public init(name: String, color: String? = nil) {
    self.name = name
    self.color = color
  }
}

public struct GitHubUser: Codable, Hashable, Sendable {
  public let login: String

  public init(login: String) {
    self.login = login
  }
}

public struct GitHubPullRequestReference: Codable, Hashable, Sendable {
  public let url: URL?

  public init(url: URL? = nil) {
    self.url = url
  }
}

public struct GitHubIssue: Codable, Hashable, Sendable {
  public let number: Int
  public let title: String
  public let state: String
  public let stateReason: String?
  public let body: String?
  public let labels: [GitHubLabel]
  public let createdAt: Date
  public let updatedAt: Date
  public let closedAt: Date?
  public let htmlUrl: URL
  public let user: GitHubUser?
  public let pullRequest: GitHubPullRequestReference?

  public init(
    number: Int,
    title: String,
    state: String,
    stateReason: String? = nil,
    body: String? = nil,
    labels: [GitHubLabel] = [],
    createdAt: Date,
    updatedAt: Date,
    closedAt: Date? = nil,
    htmlUrl: URL,
    user: GitHubUser? = nil,
    pullRequest: GitHubPullRequestReference? = nil
  ) {
    self.number = number
    self.title = title
    self.state = state
    self.stateReason = stateReason
    self.body = body
    self.labels = labels
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.closedAt = closedAt
    self.htmlUrl = htmlUrl
    self.user = user
    self.pullRequest = pullRequest
  }

  public var labelNames: Set<String> {
    Set(self.labels.map(\.name))
  }

  public var isPullRequest: Bool {
    self.pullRequest != nil
  }

  public var isOpen: Bool {
    self.state.caseInsensitiveCompare("open") == .orderedSame
  }
}

public struct GitHubGitReference: Codable, Hashable, Sendable {
  public let ref: String
  public let sha: String

  public init(ref: String, sha: String) {
    self.ref = ref
    self.sha = sha
  }
}

public struct GitHubPullRequest: Codable, Hashable, Sendable {
  public let number: Int
  public let title: String
  public let state: String
  public let body: String?
  public let labels: [GitHubLabel]
  public let draft: Bool?
  public let createdAt: Date
  public let updatedAt: Date
  public let closedAt: Date?
  public let mergedAt: Date?
  public let htmlUrl: URL
  public let head: GitHubGitReference
  public let base: GitHubGitReference
  public let user: GitHubUser?

  public init(
    number: Int,
    title: String,
    state: String,
    body: String? = nil,
    labels: [GitHubLabel] = [],
    draft: Bool? = nil,
    createdAt: Date,
    updatedAt: Date,
    closedAt: Date? = nil,
    mergedAt: Date? = nil,
    htmlUrl: URL,
    head: GitHubGitReference,
    base: GitHubGitReference,
    user: GitHubUser? = nil
  ) {
    self.number = number
    self.title = title
    self.state = state
    self.body = body
    self.labels = labels
    self.draft = draft
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.closedAt = closedAt
    self.mergedAt = mergedAt
    self.htmlUrl = htmlUrl
    self.head = head
    self.base = base
    self.user = user
  }

  public var labelNames: Set<String> {
    Set(self.labels.map(\.name))
  }

  public var isOpen: Bool {
    self.state.caseInsensitiveCompare("open") == .orderedSame
  }

  public var isMerged: Bool {
    self.mergedAt != nil
  }
}

public struct GitHubWorkflowRunsPage: Codable, Sendable {
  public let totalCount: Int
  public let workflowRuns: [GitHubWorkflowRun]

  public init(totalCount: Int, workflowRuns: [GitHubWorkflowRun]) {
    self.totalCount = totalCount
    self.workflowRuns = workflowRuns
  }
}

public struct GitHubWorkflowRun: Codable, Hashable, Sendable {
  public let id: Int64
  public let name: String
  public let displayTitle: String?
  public let path: String?
  public let status: String
  public let conclusion: String?
  public let event: String?
  public let headBranch: String?
  public let headSha: String?
  public let runNumber: Int?
  public let runAttempt: Int?
  public let createdAt: Date
  public let updatedAt: Date
  public let runStartedAt: Date?
  public let htmlUrl: URL
  public let actor: GitHubUser?

  public init(
    id: Int64,
    name: String,
    displayTitle: String? = nil,
    path: String? = nil,
    status: String,
    conclusion: String? = nil,
    event: String? = nil,
    headBranch: String? = nil,
    headSha: String? = nil,
    runNumber: Int? = nil,
    runAttempt: Int? = nil,
    createdAt: Date,
    updatedAt: Date,
    runStartedAt: Date? = nil,
    htmlUrl: URL,
    actor: GitHubUser? = nil
  ) {
    self.id = id
    self.name = name
    self.displayTitle = displayTitle
    self.path = path
    self.status = status
    self.conclusion = conclusion
    self.event = event
    self.headBranch = headBranch
    self.headSha = headSha
    self.runNumber = runNumber
    self.runAttempt = runAttempt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.runStartedAt = runStartedAt
    self.htmlUrl = htmlUrl
    self.actor = actor
  }
}

public struct GitHubWorkflowJobsPage: Codable, Sendable {
  public let totalCount: Int
  public let jobs: [GitHubWorkflowJob]

  public init(totalCount: Int, jobs: [GitHubWorkflowJob]) {
    self.totalCount = totalCount
    self.jobs = jobs
  }
}

public struct GitHubWorkflowJob: Codable, Hashable, Sendable {
  public let id: Int64
  public let name: String
  public let status: String
  public let conclusion: String?
  public let startedAt: Date?
  public let completedAt: Date?
  public let htmlUrl: URL?
  public let steps: [GitHubWorkflowStep]?

  public init(
    id: Int64,
    name: String,
    status: String,
    conclusion: String? = nil,
    startedAt: Date? = nil,
    completedAt: Date? = nil,
    htmlUrl: URL? = nil,
    steps: [GitHubWorkflowStep]? = nil
  ) {
    self.id = id
    self.name = name
    self.status = status
    self.conclusion = conclusion
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.htmlUrl = htmlUrl
    self.steps = steps
  }
}

public struct GitHubWorkflowStep: Codable, Hashable, Sendable {
  public let number: Int
  public let name: String
  public let status: String
  public let conclusion: String?
  public let startedAt: Date?
  public let completedAt: Date?

  public init(
    number: Int,
    name: String,
    status: String,
    conclusion: String? = nil,
    startedAt: Date? = nil,
    completedAt: Date? = nil
  ) {
    self.number = number
    self.name = name
    self.status = status
    self.conclusion = conclusion
    self.startedAt = startedAt
    self.completedAt = completedAt
  }
}
