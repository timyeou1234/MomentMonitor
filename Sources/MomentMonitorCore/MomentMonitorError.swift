import Foundation

public enum MomentMonitorError: Error, Equatable, Sendable {
  case invalidRepository(String)
  case executableNotFound(String)
  case commandTimedOut(seconds: TimeInterval)
  case commandFailed(exitCode: Int32, message: String)
  case invalidUTF8Output
  case invalidResponse(String)
  case unauthenticated(String)
}

extension MomentMonitorError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidRepository(let value):
      return "Invalid GitHub repository ‘\(value)’. Use owner/name."
    case .executableNotFound(let name):
      return "Could not find \(name). Install GitHub CLI with Homebrew, then run gh auth login."
    case .commandTimedOut(let seconds):
      return "GitHub CLI did not finish within \(Int(seconds)) seconds."
    case .commandFailed(_, let message):
      return message.isEmpty ? "GitHub CLI command failed." : message
    case .invalidUTF8Output:
      return "GitHub CLI returned output that was not valid UTF-8."
    case .invalidResponse(let message):
      return "GitHub returned an unexpected response: \(message)"
    case .unauthenticated(let message):
      return message.isEmpty ? "GitHub CLI is not authenticated." : message
    }
  }
}
