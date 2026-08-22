import Foundation

public enum DependencyParser {
  public static func dependencyNumbers(in body: String?) -> Set<Int> {
    guard let body, !body.isEmpty else { return [] }

    let pattern = #"<!--\s*moment:depends-on\s+([0-9,\s]+?)\s*-->"#
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    else {
      return []
    }

    let range = NSRange(body.startIndex..<body.endIndex, in: body)
    var result = Set<Int>()

    for match in expression.matches(in: body, range: range) {
      guard match.numberOfRanges > 1,
        let captureRange = Range(match.range(at: 1), in: body)
      else { continue }

      let captured = body[captureRange]
      for rawValue in captured.split(separator: ",") {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(value) {
          result.insert(number)
        }
      }
    }

    return result
  }

  public static func unresolvedDependencies(
    in body: String?,
    openIssueNumbers: Set<Int>
  ) -> [Int] {
    self.dependencyNumbers(in: body)
      .intersection(openIssueNumbers)
      .sorted()
  }
}
