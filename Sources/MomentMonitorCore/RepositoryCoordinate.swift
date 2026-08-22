import Foundation

public struct RepositoryCoordinate: Codable, Hashable, Sendable {
  public let owner: String
  public let name: String

  public init(owner: String, name: String) throws {
    let normalizedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

    guard Self.isValidSegment(normalizedOwner), Self.isValidSegment(normalizedName) else {
      throw MomentMonitorError.invalidRepository("\(owner)/\(name)")
    }

    self.owner = normalizedOwner
    self.name = normalizedName
  }

  public init(parsing rawValue: String) throws {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
    guard components.count == 2 else {
      throw MomentMonitorError.invalidRepository(rawValue)
    }
    try self.init(owner: String(components[0]), name: String(components[1]))
  }

  public var fullName: String {
    "\(self.owner)/\(self.name)"
  }

  private static func isValidSegment(_ value: String) -> Bool {
    guard !value.isEmpty, value != ".", value != "..", value.count <= 100 else { return false }
    return value.unicodeScalars.allSatisfy { scalar in
      CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" || scalar == "."
    }
  }
}

extension RepositoryCoordinate {
  public static let moment = try! RepositoryCoordinate(owner: "timyeou1234", name: "Moment")
}
