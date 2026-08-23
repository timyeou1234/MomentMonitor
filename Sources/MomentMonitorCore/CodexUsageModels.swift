import Foundation

public enum CodexUsageAvailability: String, Codable, Equatable, Sendable {
  case live
  case unavailable
}

public struct CodexUsageWindow: Codable, Equatable, Sendable {
  public let usedPercent: Double
  public let windowDurationMinutes: Int
  public let resetsAt: Date

  public init(usedPercent: Double, windowDurationMinutes: Int, resetsAt: Date) {
    self.usedPercent = min(max(usedPercent, 0), 100)
    self.windowDurationMinutes = windowDurationMinutes
    self.resetsAt = resetsAt
  }

  public var remainingPercent: Double {
    100 - self.usedPercent
  }
}

public struct CodexUsageObservation: Codable, Equatable, Sendable {
  public let availability: CodexUsageAvailability
  public let planType: String?
  public let primary: CodexUsageWindow?
  public let secondary: CodexUsageWindow?
  public let fetchedAt: Date?
  public let message: String?

  public init(
    availability: CodexUsageAvailability,
    planType: String? = nil,
    primary: CodexUsageWindow? = nil,
    secondary: CodexUsageWindow? = nil,
    fetchedAt: Date? = nil,
    message: String? = nil
  ) {
    self.availability = availability
    self.planType = planType
    self.primary = primary
    self.secondary = secondary
    self.fetchedAt = fetchedAt
    self.message = message
  }

  public static func unavailable(message: String) -> Self {
    Self(availability: .unavailable, message: message)
  }
}
