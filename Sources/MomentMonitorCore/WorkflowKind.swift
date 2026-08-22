import Foundation

public enum WorkflowKind: String, Codable, CaseIterable, Sendable {
  case scheduler
  case localTask
  case prFast
  case other

  public var displayName: String {
    switch self {
    case .scheduler: "Scheduler"
    case .localTask: "Local Codex task"
    case .prFast: "PR Fast"
    case .other: "Workflow"
    }
  }

  public static func classify(_ run: GitHubWorkflowRun) -> Self {
    let path = (run.path ?? "").lowercased()
    let name = run.name.lowercased()

    if path.hasSuffix("/codex-scheduler.yml") || path == ".github/workflows/codex-scheduler.yml"
      || name.contains("development scheduler")
    {
      return .scheduler
    }
    if path.hasSuffix("/codex-task.yml") || path == ".github/workflows/codex-task.yml"
      || name.contains("local development task")
    {
      return .localTask
    }
    if path.hasSuffix("/security.yml") || path == ".github/workflows/security.yml"
      || name == "pr fast"
    {
      return .prFast
    }
    return .other
  }

  public static func isRelevant(_ run: GitHubWorkflowRun) -> Bool {
    self.classify(run) != .other
  }
}
