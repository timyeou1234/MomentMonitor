import Foundation

public struct WorkflowProgress: Equatable, Sendable {
  public let jobName: String?
  public let stepName: String?
  public let status: String

  public init(jobName: String?, stepName: String?, status: String) {
    self.jobName = jobName
    self.stepName = stepName
    self.status = status
  }

  public var displayText: String? {
    let values = [self.jobName, self.stepName]
      .compactMap { value -> String? in
        guard let value, !value.isEmpty else { return nil }
        return value
      }
    return values.isEmpty ? nil : values.joined(separator: " · ")
  }
}

public enum RunCorrelation {
  public static func closingIssueNumber(in pullRequestBody: String?) -> Int? {
    guard let pullRequestBody, !pullRequestBody.isEmpty else { return nil }
    let pattern = #"(?im)^\s*(?:closes|fixes|resolves)\s+#(\d+)\s*$"#
    return self.firstIntegerCapture(pattern: pattern, in: pullRequestBody)
  }

  public static func issueNumber(from pullRequest: GitHubPullRequest) -> Int? {
    if let number = self.closingIssueNumber(in: pullRequest.body) {
      return number
    }
    let titlePattern = #"(?i)\b(?:implement|repair)\s+#(\d+)\b"#
    return self.firstIntegerCapture(pattern: titlePattern, in: pullRequest.title)
  }

  public static func issueNumber(from run: GitHubWorkflowRun) -> Int? {
    guard WorkflowKind.classify(run) == .localTask else { return nil }

    // pull_request_target review runs render the PR number in the run title.
    // workflow_dispatch implementation/repair runs render the Issue number.
    if run.event?.caseInsensitiveCompare("pull_request_target") == .orderedSame {
      return nil
    }

    if let displayTitle = run.displayTitle,
      let number = self.trailingNumber(in: displayTitle)
    {
      return number
    }

    if let branch = run.headBranch {
      let branchPattern = #"(?i)(?:^|/)issue-(\d+)(?:-|$)"#
      if let number = self.firstIntegerCapture(pattern: branchPattern, in: branch) {
        return number
      }
    }

    return nil
  }

  public static func pullRequestNumber(from run: GitHubWorkflowRun) -> Int? {
    switch WorkflowKind.classify(run) {
    case .prFast:
      if let linkedPullRequest = run.pullRequests?.first {
        return linkedPullRequest.number
      }
      let source = run.displayTitle ?? run.name
      return self.firstIntegerCapture(pattern: #"#(\d+)"#, in: source)
    case .localTask:
      guard run.event?.caseInsensitiveCompare("pull_request_target") == .orderedSame else {
        return nil
      }
      if let linkedPullRequest = run.pullRequests?.first {
        return linkedPullRequest.number
      }
      guard let source = run.displayTitle else { return nil }
      return self.trailingNumber(in: source)
    case .scheduler, .other:
      return nil
    }
  }

  public static func progress(from jobs: [GitHubWorkflowJob]) -> WorkflowProgress? {
    if let activeJob = jobs.first(where: { Self.normalized($0.status) == "in_progress" }) {
      let step =
        activeJob.steps?.first(where: { Self.normalized($0.status) == "in_progress" })
        ?? activeJob.steps?.first(where: {
          ["queued", "waiting", "pending", "requested"].contains(Self.normalized($0.status))
        })
      return WorkflowProgress(
        jobName: activeJob.name,
        stepName: step?.name,
        status: step?.status ?? activeJob.status
      )
    }

    if let queuedJob = jobs.first(where: {
      ["queued", "waiting", "pending", "requested"].contains(Self.normalized($0.status))
    }) {
      let step = queuedJob.steps?.first(where: {
        ["queued", "waiting", "pending", "requested"].contains(Self.normalized($0.status))
      })
      return WorkflowProgress(
        jobName: queuedJob.name,
        stepName: step?.name,
        status: step?.status ?? queuedJob.status
      )
    }

    if let failedJob = jobs.first(where: {
      Self.normalized($0.status) == "completed" && Self.isFailureConclusion($0.conclusion)
    }) {
      let failedStep = failedJob.steps?.first(where: { Self.isFailureConclusion($0.conclusion) })
      return WorkflowProgress(
        jobName: failedJob.name,
        stepName: failedStep?.name,
        status: failedStep?.conclusion ?? failedJob.conclusion ?? "failure"
      )
    }

    return nil
  }

  public static func isFailureConclusion(_ conclusion: String?) -> Bool {
    guard let conclusion else { return false }
    return ["failure", "cancelled", "timed_out", "action_required", "stale", "startup_failure"]
      .contains(Self.normalized(conclusion))
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func trailingNumber(in value: String) -> Int? {
    self.firstIntegerCapture(pattern: #"(?:^|[·\s])([0-9]+)\s*$"#, in: value)
  }

  private static func firstIntegerCapture(pattern: String, in value: String) -> Int? {
    guard let expression = try? NSRegularExpression(pattern: pattern), !value.isEmpty else {
      return nil
    }
    let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = expression.firstMatch(in: value, range: fullRange),
      match.numberOfRanges > 1,
      let captureRange = Range(match.range(at: 1), in: value)
    else { return nil }
    return Int(value[captureRange])
  }
}
