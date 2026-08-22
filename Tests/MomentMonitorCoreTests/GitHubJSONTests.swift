import XCTest

@testable import MomentMonitorCore

final class GitHubJSONTests: XCTestCase {
  func testDecodesPaginatedIssues() throws {
    let pages = try JSONDecoder.github.decode(
      [[GitHubIssue]].self, from: fixtureData("issues-pages"))
    XCTAssertEqual(pages.flatMap { $0 }.first?.number, 292)
    XCTAssertEqual(pages.flatMap { $0 }.first?.labelNames, ["dev-ready"])
  }

  func testDecodesWorkflowRunsAndJobs() throws {
    let runs = try JSONDecoder.github.decode(
      GitHubWorkflowRunsPage.self, from: fixtureData("workflow-runs"))
    let jobs = try JSONDecoder.github.decode(
      GitHubWorkflowJobsPage.self, from: fixtureData("workflow-jobs"))
    XCTAssertEqual(
      runs.workflowRuns.first?.displayTitle, "Moment local task · workflow_dispatch · 294")
    XCTAssertEqual(jobs.jobs.first?.steps?.last?.status, "in_progress")
  }
}
