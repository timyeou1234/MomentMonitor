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

    let observation = await reader.read(repository: .moment)

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

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
    XCTAssertNil(observation.status)
  }

  func testRejectsFIFOWithoutBlockingForAWriter() async throws {
    let file = self.temporaryDirectory.appendingPathComponent("current.json")
    XCTAssertEqual(Darwin.mkfifo(file.path, 0o600), 0)
    let reader = AutomationWatchdogStatusReader(
      fileURL: file,
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
    XCTAssertEqual(observation.message, "Active observer status is not a regular file.")
  }

  func testMarksOldStatusStale() async throws {
    try self.write(Self.fixture())
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid(),
      now: { fixedDate("2026-09-09T13:40:00Z") }
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .stale)
    XCTAssertEqual(observation.status?.workers.first?.workerID, "worker-0")
  }

  func testTreatsAnotherRepositoryAsAbsent() async throws {
    try self.write(Self.fixture(repository: "example/Elsewhere"))
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation, .absent)
  }

  func testRepositoryBindingIsCaseInsensitive() async throws {
    try self.write(Self.fixture(repository: "timyeou1234/Moment"))
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid(),
      now: { fixedDate("2026-09-09T13:32:00Z") }
    )

    let observation = await reader.read(
      repository: try RepositoryCoordinate(parsing: "TIMYEOU1234/moment")
    )

    XCTAssertEqual(observation.availability, .current)
  }

  func testRejectsUnknownLeaseState() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    workers[0]["lease_status"] = "finished"
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testRejectsMinimumLeaseRemainingWithoutTrapping() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    workers[0]["lease_remaining_seconds"] = Int.min
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testRejectsDuplicateWorkerIDs() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    workers.append(workers[0])
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testRejectsProducerImpossibleWorkerTopology() async throws {
    for mutation in ["unknown-worker", "duplicate-issue"] {
      var fixture = Self.fixture()
      var workers = fixture["workers"] as! [[String: Any]]
      if mutation == "unknown-worker" {
        workers[0]["worker_id"] = "worker-2"
      } else {
        var duplicate = workers[0]
        duplicate["worker_id"] = "worker-1"
        workers.append(duplicate)
      }
      fixture["workers"] = workers
      try self.write(fixture)
      let reader = AutomationWatchdogStatusReader(
        fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
        currentUserID: Darwin.getuid()
      )

      let observation = await reader.read(repository: .moment)

      XCTAssertEqual(observation.availability, .invalid, "Accepted \(mutation)")
    }
  }

  func testRejectsRuntimeAvailabilityContradiction() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    workers[0]["runtime_available"] = false
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testRejectsModelAvailabilityContradiction() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    workers[0]["model_available"] = false
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testRejectsNonAllowlistedDecisionSummary() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    var decision = workers[0]["decision"] as! [String: Any]
    decision["summary"] = "A prompt-derived summary must never be displayed."
    workers[0]["decision"] = decision
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testRejectsImpossibleDecisionStreaks() async throws {
    for (action, confidence, streak) in [
      ("observe", 0.96, 2),
      ("unblock", 0.79, 1),
      ("takeover", 0.95, 0),
    ] {
      var fixture = Self.fixture()
      var workers = fixture["workers"] as! [[String: Any]]
      var decision = workers[0]["decision"] as! [String: Any]
      decision["action"] = action
      decision["confidence"] = confidence
      decision["streak"] = streak
      decision["summary"] =
        [
          "observe": "Local model found no actionable stall.",
          "unblock": "Local model recommends bounded recovery.",
          "takeover": "Local model recommends isolated repair ownership.",
        ][action]
      workers[0]["decision"] = decision
      fixture["workers"] = workers
      try self.write(fixture)
      let reader = AutomationWatchdogStatusReader(
        fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
        currentUserID: Darwin.getuid()
      )

      let observation = await reader.read(repository: .moment)

      XCTAssertEqual(observation.availability, .invalid, "Accepted \(action) streak \(streak)")
    }
  }

  func testRejectsStateThatContradictsWorkerDecisions() async throws {
    var fixture = Self.fixture()
    fixture["state"] = "idle"
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testRejectsObservingStateWhenEveryModelIsUnavailable() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    workers[0]["model_available"] = false
    workers[0].removeValue(forKey: "decision")
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testCurrentUnavailableStatusUsesUnavailableBadge() throws {
    var fixture = Self.fixture()
    fixture["state"] = "unavailable"
    var workers = fixture["workers"] as! [[String: Any]]
    workers[0]["model_available"] = false
    workers[0].removeValue(forKey: "decision")
    fixture["workers"] = workers
    let data = try JSONSerialization.data(withJSONObject: fixture)
    let status = try AutomationWatchdogStatusReader.decodeAndValidate(data)

    XCTAssertEqual(AutomationWatchdogObservation.current(status).badgeLabel, "UNAVAILABLE")
  }

  func testRejectsContradictoryProcessActivity() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    var process = workers[0]["process"] as! [String: Any]
    process["activity"] = "absent"
    workers[0]["process"] = process
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testRejectsWaitingProcessAtWorkingCPU() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    var process = workers[0]["process"] as! [String: Any]
    process["activity"] = "waiting"
    process["max_cpu_percent"] = 999.0
    workers[0]["process"] = process
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testRejectsDuplicateKeysAtEveryContractObjectLevel() throws {
    let data = try JSONSerialization.data(
      withJSONObject: Self.fixture(), options: [.sortedKeys]
    )
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    let mutations = [
      ("{", "{\"schema\":\"moment.automation-watchdog.v1\","),
      ("\"worker_id\":\"worker-0\"", "\"worker_id\":\"worker-0\",\"worker_id\":\"worker-0\""),
      ("\"root_present\":true", "\"root_present\":true,\"root_present\":true"),
      ("\"action\":\"observe\"", "\"action\":\"observe\",\"action\":\"observe\""),
    ]

    for (needle, replacement) in mutations {
      let duplicateJSON = try XCTUnwrap(
        json.replacingFirstOccurrence(of: needle, with: replacement).data(using: .utf8)
      )

      XCTAssertThrowsError(try AutomationWatchdogStatusReader.decodeAndValidate(duplicateJSON))
    }
  }

  func testRejectsNonIdentifierModel() async throws {
    var fixture = Self.fixture()
    fixture["model"] = "Qwen\nprivate"
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  func testRejectsNonIdentifierRuntimeLabels() async throws {
    var fixture = Self.fixture()
    var workers = fixture["workers"] as! [[String: Any]]
    workers[0]["phase"] = "PR Fast"
    fixture["workers"] = workers
    try self.write(fixture)
    let reader = AutomationWatchdogStatusReader(
      fileURL: self.temporaryDirectory.appendingPathComponent("current.json"),
      currentUserID: Darwin.getuid()
    )

    let observation = await reader.read(repository: .moment)

    XCTAssertEqual(observation.availability, .invalid)
  }

  private func write(_ value: [String: Any]) throws {
    let file = self.temporaryDirectory.appendingPathComponent("current.json")
    try JSONSerialization.data(withJSONObject: value).write(to: file)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: file.path
    )
  }

  private static func fixture(repository: String = "timyeou1234/Moment") -> [String: Any] {
    [
      "schema": "moment.automation-watchdog.v1",
      "observed_at": "2026-09-09T13:31:33Z",
      "state": "observing",
      "model": "Qwen3.5-27B-4bit",
      "confidence_threshold": 0.8,
      "required_observations": 2,
      "repository": repository,
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
            "summary": "Local model found no actionable stall.",
          ],
        ]
      ],
    ]
  }
}

extension String {
  fileprivate func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
    guard let range = self.range(of: target) else { return self }
    return self.replacingCharacters(in: range, with: replacement)
  }
}
