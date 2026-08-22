import Foundation
import XCTest

@testable import MomentMonitorCore

final class GitHubCLIClientTests: XCTestCase {
  func testWorkflowRunsAndJobsRequestAllPages() async throws {
    let runsPage = try fixtureJSON("workflow-runs")
    let jobsPage = try fixtureJSON("workflow-jobs")
    let runner = CommandRunnerStub(outputs: [paginated(runsPage), paginated(jobsPage)])
    let client = GitHubCLIClient(
      executable: URL(fileURLWithPath: "/usr/bin/gh"),
      runner: runner
    )

    let runs = try await client.fetchWorkflowRuns(repository: .moment)
    let jobs = try await client.fetchWorkflowJobs(repository: .moment, runID: 1)

    XCTAssertEqual(runs.count, 2)
    XCTAssertEqual(jobs.count, 2)
    let calls = await runner.calls
    XCTAssertEqual(calls.count, 2)
    XCTAssertTrue(
      calls.allSatisfy {
        $0.arguments.contains("--paginate") && $0.arguments.contains("--slurp")
      })
  }

  private func fixtureJSON(_ name: String) throws -> Data {
    try fixtureData(name)
  }

  private func paginated(_ page: Data) -> Data {
    Data("[\(String(decoding: page, as: UTF8.self)),\(String(decoding: page, as: UTF8.self))]".utf8)
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
