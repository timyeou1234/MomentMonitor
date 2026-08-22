import XCTest

@testable import MomentMonitorCore

final class DependencyParserTests: XCTestCase {
  func testParsesMultipleMarkersAndCommaSeparatedValues() {
    let body = """
      <!-- moment:depends-on 236, 237 -->
      text
      <!-- MOMENT:DEPENDS-ON 240 -->
      """
    XCTAssertEqual(DependencyParser.dependencyNumbers(in: body), [236, 237, 240])
  }

  func testReturnsOnlyOpenDependencies() {
    let body = "<!-- moment:depends-on 236, 237, 238 -->"
    XCTAssertEqual(
      DependencyParser.unresolvedDependencies(in: body, openIssueNumbers: [237, 238, 999]),
      [237, 238]
    )
  }
}
