import Foundation

public struct MomentStateBuilder: Sendable {
  private let now: Date

  public init(now: Date = Date()) {
    self.now = now
  }

  public func build(
    configuration: MonitorConfiguration,
    issues: [GitHubIssue],
    pullRequests: [GitHubPullRequest],
    workflowRuns: [GitHubWorkflowRun],
    jobsByRunID: [Int64: [GitHubWorkflowJob]] = [:],
    runtimeObservation: AutomationRuntimeObservation = .absent
  ) -> MomentMonitorSnapshot {
    let issueItems = issues.filter { !$0.isPullRequest }
    let issueByNumber = Dictionary(uniqueKeysWithValues: issueItems.map { ($0.number, $0) })
    let openIssueNumbers = Set(issueItems.filter(\.isOpen).map(\.number))
    let pullRequestByNumber = Dictionary(uniqueKeysWithValues: pullRequests.map { ($0.number, $0) })
    let reconciledRuntimeObservation = Self.reconcileRuntimeObservation(
      runtimeObservation,
      issueByNumber: issueByNumber,
      pullRequestByNumber: pullRequestByNumber
    )
    let issueNumberByPullRequest = Dictionary(
      uniqueKeysWithValues: pullRequests.compactMap { pullRequest in
        RunCorrelation.issueNumber(from: pullRequest).map { (pullRequest.number, $0) }
      }
    )

    let relevantRuns =
      workflowRuns
      .filter(WorkflowKind.isRelevant)
      .sorted { lhs, rhs in
        if lhs.updatedAt == rhs.updatedAt { return lhs.id > rhs.id }
        return lhs.updatedAt > rhs.updatedAt
      }

    let activeRuns = relevantRuns.filter { Self.isActiveStatus($0.status) }
    let activeLocalIssueNumbers = Set(activeRuns.compactMap(RunCorrelation.issueNumber(from:)))
    let activePullRequestNumbers = Set(
      activeRuns.compactMap { run -> Int? in
        guard let pullRequestNumber = RunCorrelation.pullRequestNumber(from: run),
          let pullRequest = pullRequestByNumber[pullRequestNumber],
          Self.runMatchesPullRequestHead(run, pullRequest)
        else { return nil }
        return pullRequestNumber
      })
    let activeIssueNumbersFromPullRequestRuns = Set(
      activePullRequestNumbers.compactMap { issueNumberByPullRequest[$0] })
    let runtimeIssueNumber = reconciledRuntimeObservation.status.flatMap { status in
      [.live, .stale].contains(reconciledRuntimeObservation.availability)
        ? status.issueNumber : nil
    }
    let activeRunsForDisplay = activeRuns.filter { run in
      guard let runtimeIssueNumber else { return true }
      let directIssue = RunCorrelation.issueNumber(from: run)
      let pullRequestIssue = RunCorrelation.pullRequestNumber(from: run).flatMap {
        issueNumberByPullRequest[$0]
      }
      return (directIssue ?? pullRequestIssue) != runtimeIssueNumber
    }
    let latestRunByIssue = Self.latestRunByIssue(from: relevantRuns)
    let prFastRunsByPullRequest = Self.prFastRunsByPullRequest(from: relevantRuns)
    let automationPullRequests = pullRequests.filter(Self.isAutomationPullRequest)
    let openAutomationPullRequests = automationPullRequests.filter(\.isOpen)
    var openAutomationPullRequestByIssue: [Int: GitHubPullRequest] = [:]
    for pullRequest in openAutomationPullRequests.sorted(by: { $0.updatedAt > $1.updatedAt }) {
      guard let issueNumber = RunCorrelation.issueNumber(from: pullRequest),
        openAutomationPullRequestByIssue[issueNumber] == nil
      else { continue }
      openAutomationPullRequestByIssue[issueNumber] = pullRequest
    }

    var items: [MonitorItem] = []
    if let runtimeItem = self.runtimeItem(
      observation: reconciledRuntimeObservation,
      issueByNumber: issueByNumber,
      pullRequestByNumber: pullRequestByNumber
    ) {
      items.append(runtimeItem)
    }
    items.append(
      contentsOf: self.workQueueItems(
        issues: issueItems,
        openIssueNumbers: openIssueNumbers,
        repositoryOwner: configuration.repository.owner
      ))
    items.append(
      contentsOf: self.activeRunItems(
        runs: activeRunsForDisplay,
        issueByNumber: issueByNumber,
        pullRequestByNumber: pullRequestByNumber,
        issueNumberByPullRequest: issueNumberByPullRequest,
        openAutomationPullRequestByIssue: openAutomationPullRequestByIssue,
        jobsByRunID: jobsByRunID
      ))
    items.append(
      contentsOf: self.inferredRunningItems(
        issues: issueItems,
        activeIssueNumbers: activeLocalIssueNumbers.union(activeIssueNumbersFromPullRequestRuns),
        runtimeObservation: reconciledRuntimeObservation
      ))
    items.append(
      contentsOf: self.pullRequestItems(
        openPullRequests: openAutomationPullRequests,
        issueByNumber: issueByNumber,
        prFastRunsByPullRequest: prFastRunsByPullRequest,
        activePullRequestNumbers: activePullRequestNumbers,
        activeLocalIssueNumbers: activeLocalIssueNumbers
      ))
    items.append(
      contentsOf: self.missingPullRequestItems(
        issues: issueItems,
        automationPullRequests: automationPullRequests
      ))
    items.append(
      contentsOf: self.blockedItems(
        issues: issueItems,
        latestRunByIssue: latestRunByIssue
      ))
    let completedPullRequestByIssue = Self.completedPullRequestByIssue(
      pullRequests: automationPullRequests,
      issueByNumber: issueByNumber
    )
    items.append(
      contentsOf: self.completedItems(
        pullRequestByIssue: completedPullRequestByIssue,
        issueByNumber: issueByNumber,
        limit: configuration.completedItemLimit
      ))

    if let status = reconciledRuntimeObservation.status {
      let runnerIsLive = reconciledRuntimeObservation.availability == .live
      items = items.map { item in
        guard let issueNumber = item.issueNumber else { return item }
        return item.withAutomationDuration(
          milliseconds: status.observedDurationMilliseconds(
            for: issueNumber,
            at: self.now,
            runnerIsLive: runnerIsLive
          )
        )
      }
    }

    let m1Issues = issueItems.filter(Self.isM1Issue)
    let closedM1IssueCount = m1Issues.filter { issue in
      issue.state.caseInsensitiveCompare("closed") == .orderedSame
    }.count

    return MomentMonitorSnapshot(
      repository: configuration.repository,
      generatedAt: self.now,
      items: Self.sort(items),
      projectProgress: ProjectProgress(
        completedCount: closedM1IssueCount,
        totalCount: m1Issues.count
      ),
      runtimeObservation: reconciledRuntimeObservation
    )
  }

  private static func isM1Issue(_ issue: GitHubIssue) -> Bool {
    issue.title.range(of: "[M1]", options: [.anchored, .caseInsensitive]) != nil
  }

  private func runtimeItem(
    observation: AutomationRuntimeObservation,
    issueByNumber: [Int: GitHubIssue],
    pullRequestByNumber: [Int: GitHubPullRequest]
  ) -> MonitorItem? {
    guard [.live, .stale].contains(observation.availability),
      let status = observation.status,
      let issue = issueByNumber[status.issueNumber]
    else { return nil }

    let pullRequest = status.pullRequestNumber.flatMap { pullRequestByNumber[$0] }
    var detailParts = [status.phase.title]
    if let phaseDetail = status.phaseDetail { detailParts.append(phaseDetail) }
    if observation.availability == .live {
      detailParts.append(
        "phase running for \(RelativeTimeFormatter.compactDuration(from: status.phaseStartedAt, to: self.now))"
      )
    } else if let message = observation.message {
      detailParts.append(message)
    }

    return MonitorItem(
      id: "running:runtime:\(status.runID)",
      lane: .running,
      source: .inferredState,
      title: "#\(status.issueNumber) \(issue.title)",
      detail: detailParts.joined(separator: " · "),
      statusText: Self.runtimeBadge(status),
      issueNumber: status.issueNumber,
      pullRequestNumber: status.pullRequestNumber,
      url: pullRequest?.htmlUrl ?? issue.htmlUrl,
      updatedAt: status.phaseStartedAt,
      severity: observation.availability == .live ? .active : .warning,
      sequenceNumber: status.issueNumber
    )
  }

  private func workQueueItems(
    issues: [GitHubIssue],
    openIssueNumbers: Set<Int>,
    repositoryOwner: String
  ) -> [MonitorItem] {
    return issues.compactMap { issue -> MonitorItem? in
      let labels = issue.labelNames
      let hasReadyMarker = (issue.body ?? "").contains("<!-- moment:dev-ready -->")
      let isOwnerAuthored =
        issue.user?.login.caseInsensitiveCompare(repositoryOwner) == .orderedSame
      guard issue.isOpen,
        isOwnerAuthored,
        !labels.contains("dev-blocked"),
        !labels.contains("dev-running"),
        !labels.contains("dev-pr-open"),
        labels.contains("dev-ready") || hasReadyMarker
      else { return nil }
      let dependencies = DependencyParser.unresolvedDependencies(
        in: issue.body,
        openIssueNumbers: openIssueNumbers
      )

      if dependencies.isEmpty {
        return MonitorItem(
          id: "ready:issue:\(issue.number)",
          lane: .ready,
          source: .issue,
          title: "#\(issue.number) \(issue.title)",
          detail: "Eligible for the scheduler",
          statusText: "ready",
          issueNumber: issue.number,
          url: issue.htmlUrl,
          updatedAt: issue.updatedAt,
          severity: .normal,
          sequenceNumber: issue.number
        )
      }

      return MonitorItem(
        id: "waiting:issue:\(issue.number)",
        lane: .waiting,
        source: .issue,
        title: "#\(issue.number) \(issue.title)",
        detail: "Waiting on " + dependencies.map { "#\($0)" }.joined(separator: ", "),
        statusText: "dependency",
        issueNumber: issue.number,
        url: issue.htmlUrl,
        updatedAt: issue.updatedAt,
        severity: .normal,
        sequenceNumber: issue.number
      )
    }
  }

  private func activeRunItems(
    runs: [GitHubWorkflowRun],
    issueByNumber: [Int: GitHubIssue],
    pullRequestByNumber: [Int: GitHubPullRequest],
    issueNumberByPullRequest: [Int: Int],
    openAutomationPullRequestByIssue: [Int: GitHubPullRequest],
    jobsByRunID: [Int64: [GitHubWorkflowJob]]
  ) -> [MonitorItem] {
    runs.map { run in
      let kind = WorkflowKind.classify(run)
      let issueNumber = RunCorrelation.issueNumber(from: run)
      let pullRequestNumber = RunCorrelation.pullRequestNumber(from: run)
      let issueNumberFromPR = pullRequestNumber.flatMap { issueNumberByPullRequest[$0] }
      let resolvedIssueNumber = issueNumber ?? issueNumberFromPR
      let issue = resolvedIssueNumber.flatMap { issueByNumber[$0] }
      let pullRequest =
        pullRequestNumber.flatMap { pullRequestByNumber[$0] }
        ?? resolvedIssueNumber.flatMap { openAutomationPullRequestByIssue[$0] }
      let progress = RunCorrelation.progress(from: jobsByRunID[run.id] ?? [])
      let lane: MonitorLane = Self.isQueuedStatus(run.status) ? .queued : .running
      let severity: MonitorSeverity = lane == .running ? .active : .normal
      let startedAt = run.runStartedAt ?? run.createdAt
      let duration = RelativeTimeFormatter.compactDuration(from: startedAt, to: self.now)

      let title: String
      switch kind {
      case .localTask:
        if let issue {
          if let pullRequest, let attempt = Self.repairAttempt(labels: pullRequest.labelNames) {
            title = "Repair \(attempt) · #\(issue.number) · PR #\(pullRequest.number)"
          } else {
            title = "#\(issue.number) \(issue.title)"
          }
        } else {
          title = run.displayTitle ?? run.name
        }
      case .prFast:
        if let pullRequest, let issueNumber = resolvedIssueNumber {
          title = "PR #\(pullRequest.number) · Issue #\(issueNumber)"
        } else if let pullRequestNumber {
          title = "PR Fast · #\(pullRequestNumber)"
        } else {
          title = run.displayTitle ?? run.name
        }
      case .scheduler:
        title = "Moment scheduler"
      case .other:
        title = run.displayTitle ?? run.name
      }

      let detail: String
      if lane == .queued {
        detail = "\(kind.displayName) · waiting for the runner · \(duration)"
      } else if let progressText = progress?.displayText {
        detail = "\(progressText) · \(duration)"
      } else {
        detail = "\(kind.displayName) · running for \(duration)"
      }

      return MonitorItem(
        id: "\(lane.rawValue):run:\(run.id)",
        lane: lane,
        source: .workflowRun,
        title: title,
        detail: detail,
        statusText: run.status,
        issueNumber: resolvedIssueNumber,
        pullRequestNumber: pullRequest?.number ?? pullRequestNumber,
        workflowRunID: run.id,
        url: run.htmlUrl,
        updatedAt: run.runStartedAt ?? run.createdAt,
        severity: severity,
        sequenceNumber: resolvedIssueNumber ?? pullRequestNumber ?? run.runNumber ?? .max
      )
    }
  }

  private func inferredRunningItems(
    issues: [GitHubIssue],
    activeIssueNumbers: Set<Int>,
    runtimeObservation: AutomationRuntimeObservation
  ) -> [MonitorItem] {
    let runtimeIssueNumber = runtimeObservation.status.flatMap { status in
      [.live, .stale].contains(runtimeObservation.availability) ? status.issueNumber : nil
    }
    return issues.compactMap { issue -> MonitorItem? in
      guard issue.isOpen,
        issue.labelNames.contains("dev-running"),
        !issue.labelNames.contains("dev-blocked"),
        !activeIssueNumbers.contains(issue.number),
        issue.number != runtimeIssueNumber
      else { return nil }

      return MonitorItem(
        id: "running:inferred:\(issue.number)",
        lane: .running,
        source: .inferredState,
        title: "#\(issue.number) \(issue.title)",
        detail: "dev-running is set · runner details are local and are not published to GitHub",
        statusText: "running",
        issueNumber: issue.number,
        url: issue.htmlUrl,
        updatedAt: issue.updatedAt,
        severity: .active,
        sequenceNumber: issue.number
      )
    }
  }

  private static func reconcileRuntimeObservation(
    _ observation: AutomationRuntimeObservation,
    issueByNumber: [Int: GitHubIssue],
    pullRequestByNumber: [Int: GitHubPullRequest]
  ) -> AutomationRuntimeObservation {
    guard let status = observation.status else { return observation }
    guard let issue = issueByNumber[status.issueNumber] else {
      return .stale(status, message: "The originating Issue is not visible on GitHub.")
    }

    if observation.availability == .terminal, status.outcome == .completed {
      let pullRequest = status.pullRequestNumber.flatMap { pullRequestByNumber[$0] }
      let confirmed = !issue.isOpen && pullRequest?.isMerged == true
      return .terminal(
        status,
        message: confirmed
          ? "GitHub confirms the merged PR and closed Issue."
          : "Awaiting GitHub merged-PR and closed-Issue confirmation."
      )
    }
    return observation
  }

  private static func runtimeBadge(_ status: AutomationRuntimeStatus) -> String {
    if let model = status.model { return model.displayName }
    return switch status.phase {
    case .prFast: "PR Fast"
    case .creatingPR: "PR"
    case .verifyingExactHead: "Verify"
    case .mergingPR: "Merge"
    case .closingIssue: "Close"
    default: status.phase.stage.title
    }
  }

  private func pullRequestItems(
    openPullRequests: [GitHubPullRequest],
    issueByNumber: [Int: GitHubIssue],
    prFastRunsByPullRequest: [Int: [GitHubWorkflowRun]],
    activePullRequestNumbers: Set<Int>,
    activeLocalIssueNumbers: Set<Int>
  ) -> [MonitorItem] {
    openPullRequests.compactMap { pullRequest in
      let issueNumber = RunCorrelation.issueNumber(from: pullRequest)
      if activePullRequestNumbers.contains(pullRequest.number) {
        return nil
      }
      if let issueNumber, activeLocalIssueNumbers.contains(issueNumber) {
        return nil
      }

      let issue = issueNumber.flatMap { issueByNumber[$0] }
      let latestRun = prFastRunsByPullRequest[pullRequest.number]?.first {
        Self.runMatchesPullRequestHead($0, pullRequest)
      }
      let status = latestRun?.conclusion ?? latestRun?.status
      let isFailure = RunCorrelation.isFailureConclusion(latestRun?.conclusion)
      let repairAttempt = Self.repairAttempt(labels: pullRequest.labelNames)
      let reconciliationAge = self.now.timeIntervalSince(
        latestRun?.updatedAt ?? pullRequest.updatedAt)
      let isStaleReconciliation = reconciliationAge > 5 * 60

      let detail: String
      let statusText: String
      let severity: MonitorSeverity
      if isFailure {
        if let repairAttempt {
          detail =
            "Issue #\(issueNumber.map(String.init) ?? "?") · workflow failed after repair attempt \(repairAttempt)"
        } else {
          detail = "Issue #\(issueNumber.map(String.init) ?? "?") · PR Fast workflow failed"
        }
        statusText = status ?? "failure"
        severity = .warning
      } else if let repairAttempt {
        let noun = repairAttempt == 1 ? "attempt" : "attempts"
        detail = "\(repairAttempt) bounded repair \(noun) used · reconciling the repaired head"
        statusText = isStaleReconciliation ? "check state" : "repair path"
        severity = isStaleReconciliation ? .warning : .normal
      } else if Self.normalized(latestRun?.status) == "completed" {
        // security.yml intentionally uses continue-on-error before it decides merge vs repair.
        // A successful workflow conclusion alone cannot prove that PR Fast passed or merged.
        detail = "PR Fast workflow finished · reconciling merge state"
        statusText = isStaleReconciliation ? "check state" : "reconciling"
        severity = isStaleReconciliation ? .warning : .normal
      } else if latestRun == nil {
        detail = "Locally reviewed head · waiting for PR Fast"
        statusText = "open"
        severity = .normal
      } else {
        detail = "PR Fast workflow: \(status ?? "unknown")"
        statusText = status ?? "open"
        severity = .normal
      }

      return MonitorItem(
        id: "pr-checks:pr:\(pullRequest.number)",
        lane: .prChecks,
        source: .pullRequest,
        title: "PR #\(pullRequest.number) · \(issue?.title ?? pullRequest.title)",
        detail: detail,
        statusText: statusText,
        issueNumber: issueNumber,
        pullRequestNumber: pullRequest.number,
        url: pullRequest.htmlUrl,
        updatedAt: latestRun?.updatedAt ?? pullRequest.updatedAt,
        severity: severity,
        sequenceNumber: issueNumber ?? pullRequest.number
      )
    }
  }

  private func missingPullRequestItems(
    issues: [GitHubIssue],
    automationPullRequests: [GitHubPullRequest]
  ) -> [MonitorItem] {
    var latestPullRequestByIssue: [Int: GitHubPullRequest] = [:]
    for pullRequest in automationPullRequests.sorted(by: { $0.updatedAt > $1.updatedAt }) {
      guard let issueNumber = RunCorrelation.issueNumber(from: pullRequest),
        latestPullRequestByIssue[issueNumber] == nil
      else { continue }
      latestPullRequestByIssue[issueNumber] = pullRequest
    }

    return issues.compactMap { issue in
      guard issue.isOpen,
        issue.labelNames.contains("dev-pr-open"),
        !issue.labelNames.contains("dev-blocked")
      else { return nil }
      let latestPullRequest = latestPullRequestByIssue[issue.number]
      if latestPullRequest?.isOpen == true {
        return nil
      }

      let age = self.now.timeIntervalSince(issue.updatedAt)
      let detail: String
      let statusText: String
      let severity: MonitorSeverity
      let pullRequestNumber: Int?
      let url: URL

      if let latestPullRequest, latestPullRequest.isMerged {
        detail = "PR #\(latestPullRequest.number) merged · waiting for Issue closure to refresh"
        statusText = age > 5 * 60 ? "check state" : "merging"
        severity = age > 5 * 60 ? .warning : .normal
        pullRequestNumber = latestPullRequest.number
        url = latestPullRequest.htmlUrl
      } else if let latestPullRequest {
        detail = "dev-pr-open is set, but PR #\(latestPullRequest.number) is closed without merge"
        statusText = "check state"
        severity = .warning
        pullRequestNumber = latestPullRequest.number
        url = latestPullRequest.htmlUrl
      } else {
        detail = "dev-pr-open is set, but no automation PR was resolved"
        statusText = age > 5 * 60 ? "check state" : "publishing"
        severity = age > 5 * 60 ? .warning : .normal
        pullRequestNumber = nil
        url = issue.htmlUrl
      }

      return MonitorItem(
        id: "pr-checks:inferred:\(issue.number)",
        lane: .prChecks,
        source: .inferredState,
        title: "#\(issue.number) \(issue.title)",
        detail: detail,
        statusText: statusText,
        issueNumber: issue.number,
        pullRequestNumber: pullRequestNumber,
        url: url,
        updatedAt: issue.updatedAt,
        severity: severity,
        sequenceNumber: issue.number
      )
    }
  }

  private func blockedItems(
    issues: [GitHubIssue],
    latestRunByIssue: [Int: GitHubWorkflowRun]
  ) -> [MonitorItem] {
    issues.compactMap { issue in
      guard issue.isOpen, issue.labelNames.contains("dev-blocked") else { return nil }
      let latestRun = latestRunByIssue[issue.number]
      let status = latestRun?.conclusion ?? latestRun?.status
      let detail =
        status.map { "Automation stopped · latest run: \($0)" }
        ?? "Automation stopped; open the Issue for the recorded reason"

      return MonitorItem(
        id: "blocked:issue:\(issue.number)",
        lane: .blocked,
        source: .issue,
        title: "#\(issue.number) \(issue.title)",
        detail: detail,
        statusText: "blocked",
        issueNumber: issue.number,
        url: issue.htmlUrl,
        updatedAt: issue.updatedAt,
        severity: .warning,
        sequenceNumber: issue.number
      )
    }
  }

  private func completedItems(
    pullRequestByIssue: [Int: GitHubPullRequest],
    issueByNumber: [Int: GitHubIssue],
    limit: Int
  ) -> [MonitorItem] {
    let completed = pullRequestByIssue.map {
      (issueNumber: $0.key, pullRequest: $0.value)
    }

    return
      completed
      .sorted {
        ($0.pullRequest.mergedAt ?? .distantPast)
          > ($1.pullRequest.mergedAt ?? .distantPast)
      }
      .prefix(limit)
      .compactMap { pair in
        let issueNumber = pair.issueNumber
        let pullRequest = pair.pullRequest
        guard let issue = issueByNumber[issueNumber] else { return nil }
        let mergedAt = pullRequest.mergedAt ?? pullRequest.updatedAt
        return MonitorItem(
          id: "completed:pr:\(pullRequest.number)",
          lane: .completed,
          source: .pullRequest,
          title: "#\(issue.number) \(issue.title)",
          detail:
            "Merged via PR #\(pullRequest.number) · \(RelativeTimeFormatter.relativeDescription(from: mergedAt, to: self.now))",
          statusText: "merged",
          issueNumber: issueNumber,
          pullRequestNumber: pullRequest.number,
          url: pullRequest.htmlUrl,
          updatedAt: mergedAt,
          severity: .success,
          sequenceNumber: issueNumber
        )
      }
  }

  private static func completedPullRequestByIssue(
    pullRequests: [GitHubPullRequest],
    issueByNumber: [Int: GitHubIssue]
  ) -> [Int: GitHubPullRequest] {
    var result: [Int: GitHubPullRequest] = [:]
    for pullRequest in pullRequests.sorted(by: {
      ($0.mergedAt ?? .distantPast) > ($1.mergedAt ?? .distantPast)
    }) {
      guard pullRequest.isMerged,
        let issueNumber = RunCorrelation.issueNumber(from: pullRequest),
        let issue = issueByNumber[issueNumber],
        !issue.isOpen,
        result[issueNumber] == nil
      else { continue }
      result[issueNumber] = pullRequest
    }
    return result
  }

  private static func latestRunByIssue(from runs: [GitHubWorkflowRun]) -> [Int: GitHubWorkflowRun] {
    var result: [Int: GitHubWorkflowRun] = [:]
    for run in runs {
      guard let issueNumber = RunCorrelation.issueNumber(from: run), result[issueNumber] == nil
      else {
        continue
      }
      result[issueNumber] = run
    }
    return result
  }

  private static func prFastRunsByPullRequest(
    from runs: [GitHubWorkflowRun]
  ) -> [Int: [GitHubWorkflowRun]] {
    var result: [Int: [GitHubWorkflowRun]] = [:]
    for run in runs where WorkflowKind.classify(run) == .prFast {
      guard let pullRequestNumber = RunCorrelation.pullRequestNumber(from: run) else { continue }
      result[pullRequestNumber, default: []].append(run)
    }
    return result
  }

  private static func runMatchesPullRequestHead(
    _ run: GitHubWorkflowRun,
    _ pullRequest: GitHubPullRequest
  ) -> Bool {
    if WorkflowKind.classify(run) == .localTask,
      run.event?.caseInsensitiveCompare("pull_request_target") == .orderedSame
    {
      return run.pullRequests?.first(where: { $0.number == pullRequest.number })?.head.sha
        == pullRequest.head.sha
    }
    guard let runHeadSha = run.headSha else { return false }
    return runHeadSha == pullRequest.head.sha
  }

  private static func isAutomationPullRequest(_ pullRequest: GitHubPullRequest) -> Bool {
    if pullRequest.labelNames.contains("automation-managed") {
      return true
    }
    if (pullRequest.body ?? "").localizedCaseInsensitiveContains("moment:local-clean-review") {
      return true
    }
    return RunCorrelation.issueNumber(from: pullRequest) != nil
      && pullRequest.title.localizedCaseInsensitiveContains("Implement #")
  }

  private static func isQueuedStatus(_ status: String) -> Bool {
    ["queued", "waiting", "pending", "requested"].contains(Self.normalized(status))
  }

  private static func isActiveStatus(_ status: String) -> Bool {
    self.isQueuedStatus(status) || Self.normalized(status) == "in_progress"
  }

  private static func normalized(_ status: String?) -> String {
    status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
  }

  private static func repairAttempt(labels: Set<String>) -> Int? {
    for attempt in stride(from: 3, through: 1, by: -1) {
      if labels.contains("automation-repair-\(attempt)")
        || labels.contains("automation-ci-repair-\(attempt)")
      {
        return attempt
      }
    }
    return nil
  }

  private static func sort(_ items: [MonitorItem]) -> [MonitorItem] {
    items.sorted { lhs, rhs in
      if lhs.lane.sortOrder != rhs.lane.sortOrder {
        return lhs.lane.sortOrder < rhs.lane.sortOrder
      }

      switch lhs.lane {
      case .ready, .waiting:
        return lhs.sequenceNumber < rhs.sequenceNumber
      case .queued, .running:
        if lhs.updatedAt != rhs.updatedAt {
          return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.sequenceNumber < rhs.sequenceNumber
      case .prChecks, .blocked, .completed:
        if lhs.updatedAt != rhs.updatedAt {
          return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.sequenceNumber < rhs.sequenceNumber
      }
    }
  }
}
