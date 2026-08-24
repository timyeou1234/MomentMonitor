import Darwin
import Foundation
import XCTest

@testable import MomentMonitorCore

final class AutomationRuntimeStatusReaderTests: XCTestCase {
  func testReadsStrictLiveControllerStatus() async throws {
    try await self.withStatusFile { fileURL in
      try self.writeStatus(to: fileURL)
      let reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { $0 == 65_100 }
      )

      let observation = await reader.read(repository: .moment)

      XCTAssertEqual(observation.availability, .live)
      XCTAssertEqual(observation.status?.phase, .lunaVerification)
      XCTAssertEqual(observation.status?.model, .luna)
      XCTAssertEqual(observation.status?.roundNumber, 2)
      XCTAssertEqual(observation.status?.totalRounds, 4)
    }
  }

  func testReadsVersion2AllowlistedActivityWithoutPrivateLogContent() async throws {
    try await self.withStatusFile { fileURL in
      let activity: [String: Any] = [
        "schema_version": 1,
        "source": "app_server",
        "sequence": 2,
        "kind": "command",
        "state": "completed",
        "action": "test",
        "observed_at": "2026-08-22T06:43:02.000Z",
        "completed_commands": 1,
        "failed_commands": 0,
        "completed_file_changes": 0,
        "completed_tools": 0,
        "recent": [
          [
            "sequence": 1, "kind": "command", "state": "started", "action": "test",
            "observed_at": "2026-08-22T06:43:01.000Z",
          ],
          [
            "sequence": 2, "kind": "command", "state": "completed", "action": "test",
            "observed_at": "2026-08-22T06:43:02.000Z",
          ],
        ],
      ]
      try self.writeStatus(
        to: fileURL,
        overrides: [
          "schema_version": 2,
          "format_version": "moment.automation-runtime.v2",
          "updated_at": "2026-08-22T06:43:02.000Z",
          "activity": activity,
        ]
      )
      let reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { _ in true }
      )

      let observation = await reader.read(repository: .moment)

      XCTAssertEqual(observation.availability, .live)
      XCTAssertEqual(observation.status?.schemaVersion, 2)
      XCTAssertEqual(observation.status?.activity?.source, .appServer)
      XCTAssertEqual(observation.status?.activity?.action, .test)
      XCTAssertEqual(observation.status?.activity?.completedCommands, 1)
      let encoded = String(
        data: try JSONSerialization.data(withJSONObject: activity), encoding: .utf8)!
      XCTAssertFalse(encoded.contains("prompt"))
      XCTAssertFalse(encoded.contains("command_text"))
    }
  }

  func testReadsVersion3BoundedPerIssueDurations() async throws {
    try await self.withStatusFile { fileURL in
      try self.writeStatus(
        to: fileURL,
        overrides: [
          "schema_version": 3,
          "format_version": "moment.automation-runtime.v3",
          "activity": NSNull(),
          "issue_durations": [
            ["issue_number": 236, "duration_ms": 125_000],
            ["issue_number": 237, "duration_ms": 4_205_000],
          ],
        ]
      )
      let reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { _ in true }
      )

      let observation = await reader.read(repository: .moment)

      XCTAssertEqual(observation.availability, .live)
      XCTAssertEqual(observation.status?.schemaVersion, 3)
      XCTAssertEqual(
        observation.status?.recordedDurationMilliseconds(for: 236), 125_000)
      XCTAssertEqual(
        observation.status?.recordedDurationMilliseconds(for: 237), 4_205_000)
    }
  }

  func testVersion3DurationsRejectDuplicatesAndMissingCurrentIssue() async throws {
    try await self.withStatusFile { fileURL in
      let base: [String: Any] = [
        "schema_version": 3,
        "format_version": "moment.automation-runtime.v3",
        "activity": NSNull(),
      ]
      try self.writeStatus(
        to: fileURL,
        overrides: base.merging([
          "issue_durations": [
            ["issue_number": 237, "duration_ms": 1],
            ["issue_number": 237, "duration_ms": 2],
          ]
        ]) { _, replacement in replacement }
      )
      var reader = AutomationRuntimeStatusReader(
        fileURL: fileURL, currentUserID: getuid(), processIsAlive: { _ in true })
      var observation = await reader.read(repository: .moment)
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("durations") == true)

      try self.writeStatus(
        to: fileURL,
        overrides: base.merging([
          "issue_durations": [["issue_number": 236, "duration_ms": 1]]
        ]) { _, replacement in replacement }
      )
      reader = AutomationRuntimeStatusReader(
        fileURL: fileURL, currentUserID: getuid(), processIsAlive: { _ in true })
      observation = await reader.read(repository: .moment)
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("durations") == true)

      try self.writeStatus(
        to: fileURL,
        overrides: base.merging([
          "issue_durations": (1...192).map { number in
            ["issue_number": number, "duration_ms": number]
          } + [["issue_number": 237, "duration_ms": 237]]
        ]) { _, replacement in replacement }
      )
      reader = AutomationRuntimeStatusReader(
        fileURL: fileURL, currentUserID: getuid(), processIsAlive: { _ in true })
      observation = await reader.read(repository: .moment)
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("durations") == true)
    }
  }

  func testVersion2ActivityRejectsUnknownNestedFieldsAndInvalidTimeline() async throws {
    try await self.withStatusFile { fileURL in
      var activity: [String: Any] = [
        "schema_version": 1, "source": "exec", "sequence": 1,
        "kind": "command", "state": "started", "action": "command",
        "observed_at": "2026-08-22T06:43:01.000Z",
        "completed_commands": 0, "failed_commands": 0,
        "completed_file_changes": 0, "completed_tools": 0,
        "recent": [
          [
            "sequence": 1, "kind": "command", "state": "started", "action": "command",
            "observed_at": "2026-08-22T06:43:01.000Z", "raw_command": "private",
          ]
        ],
      ]
      try self.writeStatus(
        to: fileURL,
        overrides: [
          "schema_version": 2, "format_version": "moment.automation-runtime.v2",
          "activity": activity,
        ]
      )
      var reader = AutomationRuntimeStatusReader(
        fileURL: fileURL, currentUserID: getuid(), processIsAlive: { _ in true })
      var observation = await reader.read(repository: .moment)
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("outside the public contract") == true)

      activity["recent"] = [
        [
          "sequence": 1, "kind": "command", "state": "started", "action": "command",
          "observed_at": "2026-08-22T07:00:00.000Z",
        ]
      ]
      activity["observed_at"] = "2026-08-22T07:00:00.000Z"
      try self.writeStatus(
        to: fileURL,
        overrides: [
          "schema_version": 2, "format_version": "moment.automation-runtime.v2",
          "activity": activity,
        ]
      )
      reader = AutomationRuntimeStatusReader(
        fileURL: fileURL, currentUserID: getuid(), processIsAlive: { _ in true })
      observation = await reader.read(repository: .moment)
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("activity") == true)
    }
  }

  func testDeadRunnerMakesAnActiveRecordStale() async throws {
    try await self.withStatusFile { fileURL in
      try self.writeStatus(to: fileURL)
      let reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { _ in false }
      )

      let observation = await reader.read(repository: .moment)

      XCTAssertEqual(observation.availability, .stale)
      XCTAssertTrue(observation.message?.contains("no longer running") == true)
    }
  }

  func testTerminalRecordDoesNotDependOnProcessLiveness() async throws {
    try await self.withStatusFile { fileURL in
      try self.writeStatus(
        to: fileURL,
        overrides: [
          "phase": "completed",
          "last_active_phase": "closing_issue",
          "outcome": "completed",
          "model": NSNull(),
          "role": "controller",
          "round_number": NSNull(),
          "total_rounds": NSNull(),
          "repair_attempt": NSNull(),
          "pull_request_number": 400,
        ]
      )
      let reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { _ in false }
      )

      let observation = await reader.read(repository: .moment)

      XCTAssertEqual(observation.availability, .terminal)
      XCTAssertEqual(observation.status?.pullRequestNumber, 400)
    }
  }

  func testRepositoryMismatchIsNotPresentedAsMomentActivity() async throws {
    try await self.withStatusFile { fileURL in
      try self.writeStatus(to: fileURL, overrides: ["repository": "owner/Other"])
      let reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { _ in true }
      )

      let observation = await reader.read(repository: .moment)

      XCTAssertEqual(observation, .absent)
    }
  }

  func testUnknownFieldsAndPhaseDisagreementFailClosed() async throws {
    try await self.withStatusFile { fileURL in
      try self.writeStatus(to: fileURL, overrides: ["prompt": "must never be published"])
      var reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { _ in true }
      )
      var observation = await reader.read(repository: .moment)
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("outside the public contract") == true)

      try self.writeStatus(
        to: fileURL,
        overrides: ["phase": "sol_review", "model": "gpt-5.6-luna"]
      )
      reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { _ in true }
      )
      observation = await reader.read(repository: .moment)
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("disagree") == true)
    }
  }

  func testUnsafePermissionsAndSymbolicLinksFailClosed() async throws {
    try await self.withStatusFile { fileURL in
      try self.writeStatus(to: fileURL)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: fileURL.path
      )
      var reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { _ in true }
      )
      var observation = await reader.read(repository: .moment)
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("permissions") == true)

      let target = fileURL.deletingLastPathComponent().appendingPathComponent("target.json")
      try self.writeStatus(to: target)
      try FileManager.default.removeItem(at: fileURL)
      try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: target)
      reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { _ in true }
      )
      observation = await reader.read(repository: .moment)
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("symbolic link") == true)
    }
  }

  func testOversizedStatusFailsBeforeDecode() async throws {
    try await self.withStatusFile { fileURL in
      try Data(repeating: 0x20, count: AutomationRuntimeStatusReader.maximumBytes + 1)
        .write(to: fileURL)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: fileURL.path
      )
      let reader = AutomationRuntimeStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        processIsAlive: { _ in true }
      )

      let observation = await reader.read(repository: .moment)

      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("size boundary") == true)
    }
  }

  private func withStatusFile(
    _ operation: (URL) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("moment-runtime-reader-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await operation(directory.appendingPathComponent("current.json"))
  }

  private func writeStatus(
    to fileURL: URL,
    overrides: [String: Any] = [:]
  ) throws {
    var value: [String: Any] = [
      "schema_version": 1,
      "format_version": "moment.automation-runtime.v1",
      "repository": "timyeou1234/Moment",
      "run_id": "1787376894237",
      "issue_number": 237,
      "pull_request_number": NSNull(),
      "mode": "implement",
      "phase": "luna_verification",
      "last_active_phase": NSNull(),
      "outcome": "active",
      "model": "gpt-5.6-luna",
      "role": "reviewer",
      "round_number": 2,
      "total_rounds": 4,
      "repair_attempt": 1,
      "runner_pid": 65_100,
      "sequence": 8,
      "started_at": "2026-08-22T05:34:00.000Z",
      "phase_started_at": "2026-08-22T06:43:00.000Z",
      "updated_at": "2026-08-22T06:43:01.000Z",
      "base_sha": String(repeating: "a", count: 40),
      "head_sha": String(repeating: "b", count: 40),
    ]
    value.merge(overrides) { _, replacement in replacement }
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    try data.write(to: fileURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }
}
