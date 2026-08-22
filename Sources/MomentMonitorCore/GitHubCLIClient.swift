import Foundation

public protocol GitHubReading: Sendable {
  func verifyAuthentication() async throws
  func fetchIssues(repository: RepositoryCoordinate) async throws -> [GitHubIssue]
  func fetchPullRequests(repository: RepositoryCoordinate) async throws -> [GitHubPullRequest]
  func fetchWorkflowRuns(repository: RepositoryCoordinate) async throws -> [GitHubWorkflowRun]
  func fetchWorkflowJobs(repository: RepositoryCoordinate, runID: Int64) async throws
    -> [GitHubWorkflowJob]
}

public struct GitHubCLIClient: GitHubReading, Sendable {
  private let executable: URL
  private let runner: any CommandRunning
  private let timeout: TimeInterval

  public init(
    executable: URL,
    runner: any CommandRunning = ProcessCommandRunner(),
    timeout: TimeInterval = 20
  ) {
    self.executable = executable
    self.runner = runner
    self.timeout = timeout
  }

  public static func live(timeout: TimeInterval = 20) throws -> Self {
    try Self(executable: GHExecutableLocator.locate(), timeout: timeout)
  }

  public func verifyAuthentication() async throws {
    let result = try await self.runner.run(
      executable: self.executable,
      arguments: ["auth", "status", "--hostname", "github.com"],
      environment: Self.commandEnvironment,
      timeout: self.timeout
    )
    guard result.exitCode == 0 else {
      throw MomentMonitorError.unauthenticated(Self.errorMessage(from: result))
    }
  }

  public func fetchIssues(repository: RepositoryCoordinate) async throws -> [GitHubIssue] {
    let endpoint =
      "repos/\(repository.fullName)/issues?state=all&sort=updated&direction=desc&per_page=100"
    let data = try await self.apiGET(endpoint: endpoint, paginate: true)
    do {
      return try JSONDecoder.github.decode([[GitHubIssue]].self, from: data).flatMap { $0 }
    } catch {
      throw MomentMonitorError.invalidResponse(
        "Issues could not be decoded: \(error.localizedDescription)")
    }
  }

  public func fetchPullRequests(repository: RepositoryCoordinate) async throws
    -> [GitHubPullRequest]
  {
    let endpoint =
      "repos/\(repository.fullName)/pulls?state=all&sort=updated&direction=desc&per_page=100"
    let data = try await self.apiGET(endpoint: endpoint, paginate: true)
    do {
      return try JSONDecoder.github.decode([[GitHubPullRequest]].self, from: data).flatMap { $0 }
    } catch {
      throw MomentMonitorError.invalidResponse(
        "Pull requests could not be decoded: \(error.localizedDescription)")
    }
  }

  public func fetchWorkflowRuns(repository: RepositoryCoordinate) async throws
    -> [GitHubWorkflowRun]
  {
    let endpoint = "repos/\(repository.fullName)/actions/runs?per_page=100"
    let data = try await self.apiGET(endpoint: endpoint, paginate: true)
    do {
      return try Self.decodePages(GitHubWorkflowRunsPage.self, from: data)
        .flatMap { $0.workflowRuns }
    } catch {
      throw MomentMonitorError.invalidResponse(
        "Workflow runs could not be decoded: \(error.localizedDescription)")
    }
  }

  public func fetchWorkflowJobs(
    repository: RepositoryCoordinate,
    runID: Int64
  ) async throws -> [GitHubWorkflowJob] {
    let endpoint = "repos/\(repository.fullName)/actions/runs/\(runID)/jobs?per_page=100"
    let data = try await self.apiGET(endpoint: endpoint, paginate: true)
    do {
      return try Self.decodePages(GitHubWorkflowJobsPage.self, from: data)
        .flatMap { $0.jobs }
    } catch {
      throw MomentMonitorError.invalidResponse(
        "Workflow jobs could not be decoded: \(error.localizedDescription)")
    }
  }

  func apiGET(endpoint: String, paginate: Bool) async throws -> Data {
    let arguments = Self.apiGETArguments(endpoint: endpoint, paginate: paginate)
    let result = try await self.runner.run(
      executable: self.executable,
      arguments: arguments,
      environment: Self.commandEnvironment,
      timeout: self.timeout
    )

    guard result.exitCode == 0 else {
      throw MomentMonitorError.commandFailed(
        exitCode: result.exitCode,
        message: Self.errorMessage(from: result)
      )
    }
    return result.standardOutput
  }

  static func apiGETArguments(endpoint: String, paginate: Bool) -> [String] {
    var arguments = [
      "api",
      endpoint,
      "--method",
      "GET",
      "--header",
      "Accept: application/vnd.github+json",
      "--header",
      "X-GitHub-Api-Version: 2022-11-28",
    ]
    if paginate {
      arguments.append(contentsOf: ["--paginate", "--slurp"])
    }
    return arguments
  }

  private static func decodePages<Page: Decodable>(
    _ type: Page.Type,
    from data: Data
  ) throws -> [Page] {
    do {
      return try JSONDecoder.github.decode([Page].self, from: data)
    } catch {
      // Keep single-page responses useful for callers using a gh-compatible test double.
      return [try JSONDecoder.github.decode(Page.self, from: data)]
    }
  }

  private static let commandEnvironment: [String: String] = [
    "GH_PROMPT_DISABLED": "1",
    "NO_COLOR": "1",
    "CLICOLOR": "0",
  ]

  private static func errorMessage(from result: CommandResult) -> String {
    let data = result.standardError.isEmpty ? result.standardOutput : result.standardError
    guard let value = String(data: data, encoding: .utf8) else {
      return "GitHub CLI failed with exit code \(result.exitCode)."
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= 1_500 {
      return trimmed
    }
    return String(trimmed.prefix(1_500)) + "…"
  }
}
