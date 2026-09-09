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
    let messages = try String(decoding: payload, as: UTF8.self)
      .split(whereSeparator: \Character.isNewline)
      .map { line -> [String: Any] in
        try XCTUnwrap(
          JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
      }
    let methods = try messages.map { try XCTUnwrap($0["method"] as? String) }
    let initialize = try XCTUnwrap(messages.first)
    let parameters = try XCTUnwrap(initialize["params"] as? [String: Any])
    let clientInfo = try XCTUnwrap(parameters["clientInfo"] as? [String: Any])

    XCTAssertEqual(methods, ["initialize", "initialized", "account/rateLimits/read"])
    XCTAssertEqual(clientInfo["version"] as? String, "0.7.0")
    XCTAssertFalse(methods.contains("account/usage/read"))
    XCTAssertFalse(methods.contains(where: { $0.hasPrefix("thread/") || $0.hasPrefix("turn/") }))
  }
}
