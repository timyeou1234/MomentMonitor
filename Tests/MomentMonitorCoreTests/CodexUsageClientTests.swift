import Foundation
import XCTest

@testable import MomentMonitorCore

final class CodexUsageClientTests: XCTestCase {
  func testDecodesCanonicalRateLimitAndDerivesRemainingPercentage() async throws {
    let response = """
      {"id":0,"result":{"userAgent":"codex_cli_rs"}}
      {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":38,"windowDurationMins":10080,"resetsAt":1787882389},"secondary":{"usedPercent":12.5,"windowDurationMins":300,"resetsAt":1787490106},"planType":"pro"}}}
      """
    let client = CodexUsageClient(
      executable: URL(fileURLWithPath: "/usr/bin/false"),
      runner: CodexAppServerRunnerStub(output: Data(response.utf8)),
      now: { fixedDate("2026-08-23T08:00:00Z") }
    )

    let usage = try await client.fetchUsage()

    XCTAssertEqual(usage.availability, .live)
    XCTAssertEqual(usage.planType, "pro")
    XCTAssertEqual(usage.primary?.usedPercent, 38)
    XCTAssertEqual(usage.primary?.remainingPercent, 62)
    XCTAssertEqual(usage.primary?.windowDurationMinutes, 10_080)
    XCTAssertEqual(usage.secondary?.remainingPercent, 87.5)
    XCTAssertEqual(usage.fetchedAt, fixedDate("2026-08-23T08:00:00Z"))
    XCTAssertNil(usage.message)
  }

  func testRejectsOutOfRangeUsageInsteadOfPublishingAnEstimate() async {
    let response = """
      {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":101,"windowDurationMins":300,"resetsAt":1787490106}}}}
      """
    let client = CodexUsageClient(
      executable: URL(fileURLWithPath: "/usr/bin/false"),
      runner: CodexAppServerRunnerStub(output: Data(response.utf8))
    )

    do {
      _ = try await client.fetchUsage()
      XCTFail("Expected an invalid response")
    } catch {
      XCTAssertEqual(error as? CodexUsageError, .invalidResponse)
    }
  }

  func testExplicitCodexExecutableWorksWithFinderStyleMinimalEnvironment() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "moment-monitor-codex-locator-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("codex")
    XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )

    let located = try CodexExecutableLocator.locate(environment: [
      "MOMENT_MONITOR_CODEX_PATH": executable.path,
      "PATH": "/usr/bin:/bin",
    ])

    XCTAssertEqual(located.standardizedFileURL, executable.standardizedFileURL)
  }
}

private struct CodexAppServerRunnerStub: CodexAppServerRunning {
  let output: Data

  func readRateLimits(executable _: URL, timeout _: TimeInterval) async throws -> Data {
    self.output
  }
}
