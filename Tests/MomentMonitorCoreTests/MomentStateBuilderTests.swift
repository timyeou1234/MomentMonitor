import XCTest

@testable import MomentMonitorCore

final class MomentStateBuilderTests: XCTestCase {
  private let now = fixedDate("2026-08-21T14:00:00Z")

  func testBuildsEveryMomentsLaneWithoutTreatingWorkflowSuccessAsCompletion() {
    let issues = [
      issue(262, title: "Live environment", labels: []),
      issue(292, title: "Begin production", labels: ["dev-ready", "priority:high"]),
      issue(
        293, title: "Live AI boundary", labels: ["dev-ready"],
        body: "<!-- moment:depends-on 262 -->"),
      issue(294, title: "Capture implementation", labels: ["dev-running"]),
      issue(295, title: "Blocked implementation", labels: ["dev-blocked"]),
      issue(237, title: "Backend gateway", labels: ["dev-pr-open"]),
      issue(296, title: "Completed implementation", state: "closed"),
    ]
    let prs = [
      pullRequest(312, title: "Implement #237: Backend gateway", issueNumber: 237),
      pullRequest(
        313,
        title: "Implement #296: Completed implementation",
        state: "closed",
        issueNumber: 296,
        mergedAt: fixedDate("2026-08-21T13:30:00Z")
      ),
    ]
    let runs = [
      workflowRun(100, kind: .localTask, status: "in_progress", issueNumber: 294),
      workflowRun(101, kind: .scheduler, status: "queued"),
      workflowRun(
        102, kind: .prFast, status: "completed", conclusion: "success", pullRequestNumber: 312),
    ]
    let jobs = [
      GitHubWorkflowJob(
        id: 200,
        name: "Develop",
        status: "in_progress",
        steps: [GitHubWorkflowStep(number: 1, name: "Run Luna", status: "in_progress")]
      )
    ]

    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(completedItemLimit: 8),
      issues: issues,
      pullRequests: prs,
      workflowRuns: runs,
      jobsByRunID: [100: jobs]
    )

    XCTAssertEqual(snapshot.items(in: .ready).map(\.issueNumber), [292])
    XCTAssertEqual(snapshot.items(in: .waiting).map(\.issueNumber), [293])
    XCTAssertEqual(snapshot.items(in: .queued).map(\.workflowRunID), [101])
    XCTAssertEqual(snapshot.items(in: .running).map(\.issueNumber), [294])
    XCTAssertTrue(snapshot.items(in: .running).first?.detail.contains("Run Luna") == true)
    XCTAssertEqual(snapshot.items(in: .prChecks).map(\.pullRequestNumber), [312])
    XCTAssertEqual(snapshot.items(in: .blocked).map(\.issueNumber), [295])
    XCTAssertEqual(snapshot.items(in: .completed).map(\.issueNumber), [296])
    XCTAssertFalse(snapshot.items(in: .completed).contains(where: { $0.issueNumber == 237 }))
  }

  func testActivePRFastMovesPRFromChecksToRunnerQueue() {
    let issues = [issue(237, title: "Backend gateway", labels: ["dev-pr-open"])]
    let prs = [pullRequest(312, title: "Implement #237: Backend gateway", issueNumber: 237)]
    let runs = [workflowRun(103, kind: .prFast, status: "queued", pullRequestNumber: 312)]

    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: issues,
      pullRequests: prs,
      workflowRuns: runs
    )

    XCTAssertEqual(snapshot.items(in: .queued).first?.pullRequestNumber, 312)
    XCTAssertTrue(snapshot.items(in: .prChecks).isEmpty)
  }

  func testReadyQueueUsesSchedulerPriorityThenIssueNumber() {
    let issues = [
      issue(20, title: "Default", labels: ["dev-ready"]),
      issue(30, title: "High later", labels: ["dev-ready", "priority:high"]),
      issue(10, title: "High earlier", labels: ["dev-ready", "priority:high"]),
      issue(15, title: "Medium", labels: ["dev-ready", "priority:medium"]),
    ]

    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: issues,
      pullRequests: [],
      workflowRuns: []
    )

    XCTAssertEqual(snapshot.items(in: .ready).compactMap(\.issueNumber), [10, 30, 15, 20])
  }

  func testStaleDevRunningWithoutVisibleRunIsWarning() {
    let stale = issue(
      400,
      title: "Stale task",
      labels: ["dev-running"],
      updatedAt: fixedDate("2026-08-21T13:00:00Z")
    )
    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: [stale],
      pullRequests: [],
      workflowRuns: []
    )

    XCTAssertEqual(snapshot.items(in: .running).first?.severity, .warning)
    XCTAssertEqual(snapshot.health, .attention)
  }
  func testClosedUnmergedPRWithDevPROpenIsVisibleAsWarning() {
    let trackedIssue = issue(500, title: "Inconsistent PR state", labels: ["dev-pr-open"])
    let closedPR = pullRequest(
      501,
      title: "Implement #500: Inconsistent PR state",
      state: "closed",
      issueNumber: 500
    )

    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: [trackedIssue],
      pullRequests: [closedPR],
      workflowRuns: []
    )

    XCTAssertEqual(snapshot.items(in: .prChecks).first?.severity, .warning)
    XCTAssertTrue(
      snapshot.items(in: .prChecks).first?.detail.contains("closed without merge") == true)
  }

  func testReadyMarkerMatchesSchedulerAndConflictingStateLabelsTakePrecedence() {
    let issues = [
      issue(600, title: "Marker ready", body: "<!-- moment:dev-ready -->"),
      issue(601, title: "Running wins", labels: ["dev-ready", "dev-running"]),
      issue(602, title: "Blocked wins", labels: ["dev-ready", "dev-blocked"]),
    ]

    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: issues,
      pullRequests: [],
      workflowRuns: []
    )

    XCTAssertEqual(snapshot.items(in: .ready).compactMap(\.issueNumber), [600])
    XCTAssertEqual(snapshot.items(in: .running).compactMap(\.issueNumber), [601])
    XCTAssertEqual(snapshot.items(in: .blocked).compactMap(\.issueNumber), [602])
  }

  func testPullRequestTargetReviewRunCorrelatesThroughPRToIssueWithoutDuplicatePRLane() {
    let issues = [issue(237, title: "Backend gateway", labels: ["dev-pr-open"])]
    let prs = [pullRequest(312, title: "Implement #237: Backend gateway", issueNumber: 237)]
    let reviewRun = workflowRun(
      700, kind: .localTask, status: "in_progress", pullRequestNumber: 312,
      event: "pull_request_target")

    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: issues,
      pullRequests: prs,
      workflowRuns: [reviewRun]
    )

    XCTAssertEqual(snapshot.items(in: .running).first?.issueNumber, 237)
    XCTAssertEqual(snapshot.items(in: .running).first?.pullRequestNumber, 312)
    XCTAssertTrue(snapshot.items(in: .prChecks).isEmpty)
  }

  func testMergedPRIsNotCompletedUntilOriginatingIssueIsClosed() {
    let openIssue = issue(700, title: "Still reconciling", labels: ["dev-pr-open"])
    let mergedPR = pullRequest(
      701, title: "Implement #700: Still reconciling", state: "closed", issueNumber: 700,
      mergedAt: fixedDate("2026-08-21T13:50:00Z"))

    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: [openIssue],
      pullRequests: [mergedPR],
      workflowRuns: []
    )

    XCTAssertTrue(snapshot.items(in: .completed).isEmpty)
    XCTAssertEqual(snapshot.items(in: .prChecks).first?.pullRequestNumber, 701)
  }

  func testCompletedPRFastWorkflowDoesNotClaimChecksPassedWhilePRRemainsOpen() {
    let trackedIssue = issue(710, title: "Needs reconciliation", labels: ["dev-pr-open"])
    let openPR = pullRequest(711, title: "Implement #710: Needs reconciliation", issueNumber: 710)
    let completedRun = workflowRun(
      712, kind: .prFast, status: "completed", conclusion: "success", pullRequestNumber: 711,
      createdAt: fixedDate("2026-08-21T13:59:00Z"))

    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: [trackedIssue],
      pullRequests: [openPR],
      workflowRuns: [completedRun]
    )

    let item = snapshot.items(in: .prChecks).first
    XCTAssertEqual(item?.statusText, "reconciling")
    XCTAssertTrue(item?.detail.contains("reconciling merge state") == true)
    XCTAssertFalse(item?.detail.localizedCaseInsensitiveContains("passed") == true)
  }

  func testPRFastRunForAnOlderHeadDoesNotDescribeTheCurrentPR() {
    let trackedIssue = issue(713, title: "Changed after checks", labels: ["dev-pr-open"])
    let currentHead = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    let oldHead = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    let openPR = pullRequest(
      714,
      title: "Implement #713: Changed after checks",
      issueNumber: 713,
      headSha: currentHead
    )
    let oldHeadRun = workflowRun(
      715,
      kind: .prFast,
      status: "completed",
      conclusion: "success",
      pullRequestNumber: 714,
      createdAt: fixedDate("2026-08-21T13:59:00Z"),
      headSha: oldHead
    )

    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: [trackedIssue],
      pullRequests: [openPR],
      workflowRuns: [oldHeadRun]
    )

    let item = snapshot.items(in: .prChecks).first
    XCTAssertEqual(item?.statusText, "open")
    XCTAssertTrue(item?.detail.contains("waiting for PR Fast") == true)
  }

  func testReadyQueueMatchesSchedulerOwnerAuthorshipRule() {
    let ownerIssue = issue(720, title: "Owner task", labels: ["dev-ready"])
    let collaboratorIssue = issue(
      721, title: "Collaborator task", labels: ["dev-ready"], authorLogin: "someone-else")

    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: [collaboratorIssue, ownerIssue],
      pullRequests: [],
      workflowRuns: []
    )

    XCTAssertEqual(snapshot.items(in: .ready).compactMap(\.issueNumber), [720])
  }

}
