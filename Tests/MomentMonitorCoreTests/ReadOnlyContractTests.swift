import XCTest

@testable import MomentMonitorCore

final class ReadOnlyContractTests: XCTestCase {
  func testEveryAPICommandForcesGET() {
    let arguments = GitHubCLIClient.apiGETArguments(
      endpoint: "repos/timyeou1234/Moment/actions/runs?per_page=100",
      paginate: false
    )
    XCTAssertTrue(arguments.contains("GET"))
    XCTAssertFalse(
      arguments.contains(where: { ["POST", "PATCH", "PUT", "DELETE"].contains($0.uppercased()) }))
    XCTAssertFalse(
      arguments.contains(where: { ["--field", "--raw-field", "--input"].contains($0) }))
  }

  func testPaginationUsesSlurpForValidJSON() {
    let arguments = GitHubCLIClient.apiGETArguments(
      endpoint: "repos/timyeou1234/Moment/issues?per_page=100",
      paginate: true
    )
    XCTAssertTrue(arguments.contains("--paginate"))
    XCTAssertTrue(arguments.contains("--slurp"))
  }
}
