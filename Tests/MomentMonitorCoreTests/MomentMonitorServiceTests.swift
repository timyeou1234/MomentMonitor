import XCTest

@testable import MomentMonitorCore

final class MomentMonitorServiceTests: XCTestCase {
  func testActiveStatusMatchingIsCaseInsensitiveWhenFetchingJobProgress() async throws {
    let run = workflowRun(
      900,
      kind: .localTask,
      status: " IN_PROGRESS ",
      issueNumber: 901
    )
    let reader = GitHubReaderStub(
      issues: [issue(901, title: "Case-insensitive status", labels: ["dev-running"])],
      workflowRuns: [run]
    )
    let service = MomentMonitorService(reader: reader)

    let snapshot = try await service.refresh(configuration: MonitorConfiguration())
    let requestedJobRunIDs = await reader.requestedJobRunIDs

    XCTAssertEqual(requestedJobRunIDs, [900])
    XCTAssertTrue(snapshot.items(in: .running).first?.detail.contains("Run Luna") == true)
  }
}

private actor GitHubReaderStub: GitHubReading {
  let issues: [GitHubIssue]
  let workflowRuns: [GitHubWorkflowRun]
  private(set) var requestedJobRunIDs: [Int64] = []

  init(issues: [GitHubIssue], workflowRuns: [GitHubWorkflowRun]) {
    self.issues = issues
    self.workflowRuns = workflowRuns
  }

  func verifyAuthentication() async throws {}

  func fetchIssues(repository: RepositoryCoordinate) async throws -> [GitHubIssue] {
    self.issues
  }

  func fetchPullRequests(repository: RepositoryCoordinate) async throws -> [GitHubPullRequest] {
    []
  }

  func fetchWorkflowRuns(repository: RepositoryCoordinate) async throws -> [GitHubWorkflowRun] {
    self.workflowRuns
  }

  func fetchWorkflowJobs(
    repository: RepositoryCoordinate,
    runID: Int64
  ) async throws -> [GitHubWorkflowJob] {
    self.requestedJobRunIDs.append(runID)
    return [
      GitHubWorkflowJob(
        id: 902,
        name: "Develop",
        status: "IN_PROGRESS",
        steps: [GitHubWorkflowStep(number: 1, name: "Run Luna", status: "IN_PROGRESS")]
      )
    ]
  }
}
