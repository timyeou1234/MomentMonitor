import XCTest

@testable import MomentMonitorCore

final class RunCorrelationTests: XCTestCase {
  func testParsesExactClosingIssueLine() {
    XCTAssertEqual(RunCorrelation.closingIssueNumber(in: "Intro\n\nCloses #237\n"), 237)
    XCTAssertNil(RunCorrelation.closingIssueNumber(in: "This closes #237 eventually"))
  }

  func testCorrelatesLocalTaskAndPRFastTitles() {
    let local = workflowRun(1, kind: .localTask, status: "in_progress", issueNumber: 294)
    let fast = workflowRun(2, kind: .prFast, status: "queued", pullRequestNumber: 312)
    XCTAssertEqual(RunCorrelation.issueNumber(from: local), 294)
    XCTAssertEqual(RunCorrelation.pullRequestNumber(from: fast), 312)
  }

  func testPullRequestTargetLocalTaskTreatsTrailingNumberAsPR() {
    let review = workflowRun(
      3, kind: .localTask, status: "in_progress", pullRequestNumber: 312,
      event: "pull_request_target")
    XCTAssertNil(RunCorrelation.issueNumber(from: review))
    XCTAssertEqual(RunCorrelation.pullRequestNumber(from: review), 312)
  }

  func testRESTPullRequestRelationshipWinsOverAmbiguousDisplayTitle() {
    let run = workflowRun(
      4,
      kind: .prFast,
      status: "queued",
      pullRequestNumber: 312
    )

    XCTAssertEqual(RunCorrelation.pullRequestNumber(from: run), 312)
  }

  func testWorkflowDispatchDoesNotTreatAssociatedCommitPullRequestAsItsTarget() {
    let run = workflowRun(
      5,
      kind: .localTask,
      status: "queued",
      issueNumber: 294,
      pullRequestNumber: 312,
      event: "workflow_dispatch"
    )

    XCTAssertEqual(RunCorrelation.issueNumber(from: run), 294)
    XCTAssertNil(RunCorrelation.pullRequestNumber(from: run))
  }

  func testFindsCurrentWorkflowStep() {
    let job = GitHubWorkflowJob(
      id: 1,
      name: "Develop",
      status: "in_progress",
      steps: [
        GitHubWorkflowStep(number: 1, name: "Prepare", status: "completed", conclusion: "success"),
        GitHubWorkflowStep(number: 2, name: "Run Luna", status: "in_progress"),
      ]
    )
    XCTAssertEqual(RunCorrelation.progress(from: [job])?.displayText, "Develop · Run Luna")
  }

  func testStatusMatchingIsCaseInsensitiveAndIncludesStartupFailure() {
    let job = GitHubWorkflowJob(
      id: 2,
      name: "Develop",
      status: "IN_PROGRESS",
      steps: [GitHubWorkflowStep(number: 1, name: "Run Luna", status: "IN_PROGRESS")]
    )

    XCTAssertEqual(RunCorrelation.progress(from: [job])?.displayText, "Develop · Run Luna")
    XCTAssertTrue(RunCorrelation.isFailureConclusion("STARTUP_FAILURE"))
  }
}
