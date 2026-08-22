import Foundation
import XCTest

@testable import MomentMonitorCore

final class GitHubCLIClientTests: XCTestCase {
  func testIssuesAndPullRequestsPaginateWhileWorkflowContextStaysBounded() async throws {
    let issuePages = try fixtureJSON("issues-pages")
    let runsPage = try fixtureJSON("workflow-runs")
    let jobsPage = try fixtureJSON("workflow-jobs")
    let runner = CommandRunnerStub(
      outputs: [issuePages, Data("[[]]".utf8), runsPage, jobsPage])
    let client = GitHubCLIClient(
      executable: URL(fileURLWithPath: "/usr/bin/gh"),
      runner: runner
    )

    let issues = try await client.fetchIssues(repository: .moment)
    let pullRequests = try await client.fetchPullRequests(repository: .moment)
    let runs = try await client.fetchWorkflowRuns(repository: .moment)
    let jobs = try await client.fetchWorkflowJobs(repository: .moment, runID: 1)

    XCTAssertEqual(issues.count, 1)
    XCTAssertTrue(pullRequests.isEmpty)
    XCTAssertEqual(runs.count, 1)
    XCTAssertEqual(jobs.count, 1)
    let calls = await runner.calls
    XCTAssertEqual(calls.count, 4)
    XCTAssertTrue(calls[0].arguments.contains("--paginate"))
    XCTAssertTrue(calls[0].arguments.contains("--slurp"))
    XCTAssertTrue(calls[1].arguments.contains("--paginate"))
    XCTAssertTrue(calls[1].arguments.contains("--slurp"))
    XCTAssertFalse(calls[2].arguments.contains("--paginate"))
    XCTAssertFalse(calls[2].arguments.contains("--slurp"))
    XCTAssertFalse(calls[3].arguments.contains("--paginate"))
    XCTAssertFalse(calls[3].arguments.contains("--slurp"))
  }

  private func fixtureJSON(_ name: String) throws -> Data {
    try fixtureData(name)
  }
}

private actor CommandRunnerStub: CommandRunning {
  struct Call: Sendable {
    let arguments: [String]
  }

  private var outputs: [Data]
  private(set) var calls: [Call] = []

  init(outputs: [Data]) {
    self.outputs = outputs
  }

  func run(
    executable: URL,
    arguments: [String],
    environment: [String: String],
    timeout: TimeInterval
  ) async throws -> CommandResult {
    self.calls.append(Call(arguments: arguments))
    return CommandResult(
      exitCode: 0,
      standardOutput: self.outputs.removeFirst(),
      standardError: Data()
    )
  }
}
