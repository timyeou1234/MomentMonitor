import Darwin
import Foundation
import XCTest

@testable import MomentMonitorCore

final class AutomationWatchdogStatusReaderTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    self.temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("moment-watchdog-reader-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: self.temporaryDirectory, withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: self.temporaryDirectory)
  }

  func testReadsStrictRedactedCurrentStatus() async throws {
    let file = self.temporaryDirectory.appendingPathComponent("current.json")
    try self.write(Self.fixture())
    let reader = AutomationWatchdogStatusReader(
      fileURL: file,
      currentUserID: Darwin.getuid(),
      now: { fixedDate("2026-09-09T13:32:00Z") }
    )

    let observation = await reader.read()

    XCTAssertEqual(observation.availability, .current)
    XCTAssertEqual(observation.status?.state, .observing)
    XCTAssertEqual(observation.status?.workers.first?.issueNumber, 682)
    XCTAssertEqual(observation.status?.workers.first?.process.activityKind, "compiler")
    XCTAssertEqual(observation.status?.workers.first?.decision?.action, .observe)
  }

  func testRejectsUnknownPrivateProcessIdentityField() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    workers[0]["runner_pid"] = 1234
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read()

    XCTAssertEqual(observation.availability, .invalid)
    XCTAssertNil(observation.status)
  }

  func testMarksOldStatusStale() async throws {
    try self.write(Self.fixture())
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid(),
      now: { fixedDate("2026-09-09T13:40:00Z") }
    )

    let observation = await reader.read()

    XCTAssertEqual(observation.availability, .stale)
    XCTAssertEqual(observation.status?.workers.first?.workerID, "worker-0")
  }

  private func write(_ value: [String: Any]) throws {
    let file = self.temporaryDirectory.appendingPathComponent("current.json")
    try JSONSerialization.data(withJSONObject: value).write(to: file)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: file.path
    )
  }

  private static func fixture() -> [String: Any] {
    [
      "schema": "moment.automation-watchdog.v1",
      "observed_at": "2026-09-09T13:31:33Z",
      "state": "observing",
      "model": "Qwen3.5-27B-4bit",
      "confidence_threshold": 0.8,
      "required_observations": 2,
      "repository": "timyeou1234/Moment",
      "workers": [
        [
          "worker_id": "worker-0",
          "issue_number": 682,
          "lease_status": "running",
          "lease_age_seconds": 60,
          "lease_remaining_seconds": 3_000,
          "runtime_available": true,
          "runtime_age_seconds": 27,
          "phase": "pr_fast",
          "role": "validator",
          "model_available": true,
          "process": [
            "root_present": true,
            "descendant_count": 4,
            "max_cpu_percent": 98.4,
            "activity_kind": "compiler",
            "activity": "working",
          ],
          "decision": [
            "action": "observe",
            "confidence": 0.96,
            "streak": 0,
            "required_streak": 2,
            "decided_at": "2026-09-09T13:31:33Z",
            "summary": "Normal compiler activity is visible.",
          ],
        ]
      ],
    ]
  }
}
