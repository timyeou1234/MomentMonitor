import Foundation

@testable import MomentMonitorCore

func fixedDate(_ value: String) -> Date {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.date(from: value)!
}

func fixtureData(_ name: String, file: StaticString = #filePath) throws -> Data {
  guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
    throw NSError(
      domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name)"])
  }
  return try Data(contentsOf: url)
}

func issue(
  _ number: Int,
  title: String,
  state: String = "open",
  labels: [String] = [],
  body: String? = nil,
  updatedAt: Date = fixedDate("2026-08-21T12:00:00Z"),
  authorLogin: String = "timyeou1234"
) -> GitHubIssue {
  GitHubIssue(
    number: number,
    title: title,
    state: state,
    stateReason: state == "closed" ? "completed" : nil,
    body: body,
    labels: labels.map { GitHubLabel(name: $0) },
    createdAt: fixedDate("2026-08-20T12:00:00Z"),
    updatedAt: updatedAt,
    closedAt: state == "closed" ? updatedAt : nil,
    htmlUrl: URL(string: "https://github.com/timyeou1234/Moment/issues/\(number)")!,
    user: GitHubUser(login: authorLogin)
  )
}

func pullRequest(
  _ number: Int,
  title: String,
  state: String = "open",
  issueNumber: Int,
  labels: [String] = ["automation-managed", "auto-merge", "local-review-passed"],
  mergedAt: Date? = nil,
  updatedAt: Date = fixedDate("2026-08-21T12:00:00Z"),
  headSha: String = "0123456789012345678901234567890123456789"
) -> GitHubPullRequest {
  GitHubPullRequest(
    number: number,
    title: title,
    state: state,
    body:
      "Closes #\(issueNumber)\n\n<!-- moment:local-clean-review head=0123456789012345678901234567890123456789 result=pass -->",
    labels: labels.map { GitHubLabel(name: $0) },
    draft: false,
    createdAt: fixedDate("2026-08-21T10:00:00Z"),
    updatedAt: updatedAt,
    closedAt: mergedAt,
    mergedAt: mergedAt,
    htmlUrl: URL(string: "https://github.com/timyeou1234/Moment/pull/\(number)")!,
    head: GitHubGitReference(
      ref: "automation/issue-\(issueNumber)-1", sha: headSha),
    base: GitHubGitReference(ref: "main", sha: "abcdefabcdefabcdefabcdefabcdefabcdefabcd"),
    user: GitHubUser(login: "github-actions[bot]")
  )
}

func workflowRun(
  _ id: Int64,
  kind: WorkflowKind,
  status: String,
  conclusion: String? = nil,
  issueNumber: Int? = nil,
  pullRequestNumber: Int? = nil,
  event: String = "workflow_dispatch",
  createdAt: Date = fixedDate("2026-08-21T12:00:00Z"),
  headSha: String = "0123456789012345678901234567890123456789",
  pullRequestHeadSha: String? = nil
) -> GitHubWorkflowRun {
  let name: String
  let displayTitle: String
  let path: String
  switch kind {
  case .localTask:
    name = "Moment Local Development Task"
    let renderedNumber =
      event == "pull_request_target" ? (pullRequestNumber ?? 0) : (issueNumber ?? 0)
    displayTitle = "Moment local task · \(event) · \(renderedNumber)"
    path = ".github/workflows/codex-task.yml"
  case .prFast:
    name = "PR Fast"
    displayTitle = "PR Fast · #\(pullRequestNumber ?? 0)"
    path = ".github/workflows/security.yml"
  case .scheduler:
    name = "Moment Development Scheduler"
    displayTitle = "Moment scheduler · workflow_dispatch"
    path = ".github/workflows/codex-scheduler.yml"
  case .other:
    name = "Other"
    displayTitle = "Other"
    path = ".github/workflows/other.yml"
  }

  return GitHubWorkflowRun(
    id: id,
    name: name,
    displayTitle: displayTitle,
    path: path,
    status: status,
    conclusion: conclusion,
    event: event,
    headBranch: "main",
    headSha: headSha,
    runNumber: Int(id),
    runAttempt: 1,
    createdAt: createdAt,
    updatedAt: createdAt,
    runStartedAt: status == "in_progress" ? createdAt : nil,
    htmlUrl: URL(string: "https://github.com/timyeou1234/Moment/actions/runs/\(id)")!,
    actor: GitHubUser(login: "github-actions[bot]"),
    pullRequests: pullRequestNumber.map { number in
      [
        GitHubWorkflowPullRequest(
          number: number,
          head: GitHubGitReference(
            ref: "automation/issue-\(issueNumber ?? 0)",
            sha: pullRequestHeadSha ?? headSha
          ),
          base: GitHubGitReference(
            ref: "main", sha: "abcdefabcdefabcdefabcdefabcdefabcdefabcd")
        )
      ]
    } ?? []
  )
}

func runtimeStatus(
  issueNumber: Int,
  pullRequestNumber: Int? = nil,
  phase: AutomationRuntimePhase = .lunaImplementation,
  lastActivePhase: AutomationRuntimePhase? = nil,
  outcome: AutomationRuntimeOutcome = .active,
  model: AutomationRuntimeModel? = .luna,
  role: AutomationRuntimeRole? = .implementer,
  roundNumber: Int? = nil,
  totalRounds: Int? = nil,
  repairAttempt: Int? = nil,
  phaseStartedAt: Date = fixedDate("2026-08-21T13:30:00Z"),
  activity: AutomationRuntimeActivity? = nil,
  issueDurations: [AutomationIssueDuration]? = nil
) -> AutomationRuntimeStatus {
  AutomationRuntimeStatus(
    schemaVersion: issueDurations == nil ? (activity == nil ? 1 : 2) : 3,
    formatVersion: issueDurations == nil
      ? (activity == nil ? "moment.automation-runtime.v1" : "moment.automation-runtime.v2")
      : "moment.automation-runtime.v3",
    repository: "timyeou1234/Moment",
    runID: "run-\(issueNumber)",
    issueNumber: issueNumber,
    pullRequestNumber: pullRequestNumber,
    mode: .implement,
    phase: phase,
    lastActivePhase: lastActivePhase,
    outcome: outcome,
    model: model,
    role: role,
    roundNumber: roundNumber,
    totalRounds: totalRounds,
    repairAttempt: repairAttempt,
    runnerPID: 65_100,
    sequence: 3,
    startedAt: fixedDate("2026-08-21T13:00:00Z"),
    phaseStartedAt: phaseStartedAt,
    updatedAt: phaseStartedAt,
    baseSHA: String(repeating: "a", count: 40),
    headSHA: String(repeating: "b", count: 40),
    activity: activity,
    issueDurations: issueDurations
  )
}
