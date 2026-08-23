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

  func testCodexAppServerMessagesAreUsageReadOnly() throws {
    let payload = ProcessCodexAppServerRunner.rateLimitRequestPayload()
    let methods = try String(decoding: payload, as: UTF8.self)
      .split(whereSeparator: \Character.isNewline)
      .map { line -> String in
        let object = try XCTUnwrap(
          JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        return try XCTUnwrap(object["method"] as? String)
      }

    XCTAssertEqual(methods, ["initialize", "initialized", "account/rateLimits/read"])
    XCTAssertFalse(methods.contains("account/usage/read"))
    XCTAssertFalse(methods.contains(where: { $0.hasPrefix("thread/") || $0.hasPrefix("turn/") }))
  }
}
