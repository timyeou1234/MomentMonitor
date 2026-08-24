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

  func testOldObservationStopsClaimingLiveCapacity() {
    let fetchedAt = fixedDate("2026-08-23T08:00:00Z")
    let observation = CodexUsageObservation(
      availability: .live,
      primary: CodexUsageWindow(
        usedPercent: 44,
        windowDurationMinutes: 10_080,
        resetsAt: fixedDate("2026-08-28T01:59:49Z")
      ),
      fetchedAt: fetchedAt
    )

    let stale = observation.enforcingFreshness(
      at: fixedDate("2026-08-23T08:03:01Z")
    )

    XCTAssertEqual(stale.availability, .stale)
    XCTAssertEqual(stale.fetchedAt, fetchedAt)
    XCTAssertNil(stale.primary)
    XCTAssertNil(stale.secondary)
    XCTAssertEqual(stale.message, "Codex capacity has not refreshed recently.")
  }

  func testRecentObservationRemainsLive() {
    let observation = CodexUsageObservation(
      availability: .live,
      primary: CodexUsageWindow(
        usedPercent: 2,
        windowDurationMinutes: 10_080,
        resetsAt: fixedDate("2026-08-30T01:59:49Z")
      ),
      fetchedAt: fixedDate("2026-08-24T02:00:00Z")
    )

    XCTAssertEqual(
      observation.enforcingFreshness(at: fixedDate("2026-08-24T02:02:59Z")),
      observation
    )
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

  #if os(macOS)
    func testUnresponsiveAppServerIsForceStoppedAtTheTimeout() async throws {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("moment-monitor-codex-timeout-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }

      let executable = directory.appendingPathComponent("codex")
      let program = """
        #!/usr/bin/python3
        import signal
        import time
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        time.sleep(30)
        """
      try Data(program.utf8).write(to: executable)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path
      )

      let startedAt = Date()
      do {
        _ = try await ProcessCodexAppServerRunner().readRateLimits(
          executable: executable,
          timeout: 0.1
        )
        XCTFail("Expected the unresponsive process to time out")
      } catch {
        XCTAssertEqual(error as? CodexUsageError, .timedOut)
      }
      XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }
  #endif
}

private struct CodexAppServerRunnerStub: CodexAppServerRunning {
  let output: Data

  func readRateLimits(executable _: URL, timeout _: TimeInterval) async throws -> Data {
    self.output
  }
}
