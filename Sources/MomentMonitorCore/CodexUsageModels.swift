import Foundation

public enum CodexUsageAvailability: String, Codable, Equatable, Sendable {
  case live
  case stale
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
  public static let maximumLiveAge: TimeInterval = 180

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

  public func enforcingFreshness(
    at now: Date,
    maximumAge: TimeInterval = Self.maximumLiveAge
  ) -> Self {
    guard self.availability == .live else { return self }
    guard let fetchedAt = self.fetchedAt,
      now.timeIntervalSince(fetchedAt) >= -30,
      now.timeIntervalSince(fetchedAt) <= maximumAge
    else {
      return Self(
        availability: .stale,
        fetchedAt: self.fetchedAt,
        message: "Codex capacity has not refreshed recently."
      )
    }
    return self
  }
}
