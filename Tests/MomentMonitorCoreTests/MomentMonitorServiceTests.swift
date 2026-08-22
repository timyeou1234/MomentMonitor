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

  func testRefreshCombinesOptionalLocalRuntimeStatusWithGitHubTruth() async throws {
    let trackedIssue = issue(903, title: "Runtime status", labels: ["dev-running"])
    let status = runtimeStatus(
      issueNumber: 903,
      phase: .solReview,
      model: .sol,
      role: .reviewer,
      roundNumber: 1,
      totalRounds: 4
    )
    let service = MomentMonitorService(
      reader: GitHubReaderStub(issues: [trackedIssue], workflowRuns: []),
      runtimeReader: RuntimeReaderStub(observation: .live(status))
    )

    let snapshot = try await service.refresh(configuration: MonitorConfiguration())

    XCTAssertEqual(snapshot.runtimeObservation.availability, .live)
    XCTAssertEqual(snapshot.items(in: .running).first?.statusText, "Sol")
    XCTAssertTrue(snapshot.items(in: .running).first?.detail.contains("Sol review") == true)
  }
}

private struct RuntimeReaderStub: AutomationRuntimeStatusReading {
  let observation: AutomationRuntimeObservation

  func read(repository: RepositoryCoordinate) async -> AutomationRuntimeObservation {
    self.observation
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
