import Foundation

public struct MomentMonitorService: Sendable {
  private let reader: any GitHubReading

  public init(reader: any GitHubReading) {
    self.reader = reader
  }

  public static func live() throws -> Self {
    Self(reader: try GitHubCLIClient.live())
  }

  public func verifyPrerequisites() async throws {
    try await self.reader.verifyAuthentication()
  }

  public func refresh(configuration: MonitorConfiguration) async throws -> MomentMonitorSnapshot {
    async let issuesTask = self.reader.fetchIssues(repository: configuration.repository)
    async let pullRequestsTask = self.reader.fetchPullRequests(repository: configuration.repository)
    async let workflowRunsTask = self.reader.fetchWorkflowRuns(repository: configuration.repository)

    let (issues, pullRequests, workflowRuns) = try await (
      issuesTask,
      pullRequestsTask,
      workflowRunsTask
    )

    let activeRuns = workflowRuns.filter { run in
      guard WorkflowKind.isRelevant(run) else { return false }
      return ["queued", "waiting", "pending", "requested", "in_progress"].contains(run.status)
    }

    let jobsByRunID = try await withThrowingTaskGroup(
      of: (Int64, [GitHubWorkflowJob])?.self,
      returning: [Int64: [GitHubWorkflowJob]].self
    ) { group in
      for run in activeRuns {
        group.addTask {
          do {
            let jobs = try await self.reader.fetchWorkflowJobs(
              repository: configuration.repository,
              runID: run.id
            )
            return (run.id, jobs)
          } catch is CancellationError {
            throw CancellationError()
          } catch {
            return nil
          }
        }
      }

      var result: [Int64: [GitHubWorkflowJob]] = [:]
      for try await value in group {
        if let value {
          result[value.0] = value.1
        }
      }
      return result
    }

    return MomentStateBuilder().build(
      configuration: configuration,
      issues: issues,
      pullRequests: pullRequests,
      workflowRuns: workflowRuns,
      jobsByRunID: jobsByRunID
    )
  }
}
