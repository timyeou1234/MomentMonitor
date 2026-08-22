import Foundation

public enum RelativeTimeFormatter {
  public static func compactDuration(from start: Date, to end: Date) -> String {
    let seconds = max(0, Int(end.timeIntervalSince(start)))
    if seconds < 60 {
      return "\(seconds)s"
    }
    let minutes = seconds / 60
    if minutes < 60 {
      return "\(minutes)m"
    }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if hours < 24 {
      return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }
    let days = hours / 24
    return "\(days)d"
  }

  public static func relativeDescription(from date: Date, to now: Date = Date()) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 10 { return "just now" }
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    return "\(days)d ago"
  }
}
