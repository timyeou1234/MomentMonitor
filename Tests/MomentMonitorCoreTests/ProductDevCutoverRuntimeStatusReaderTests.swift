import Darwin
import Foundation
import XCTest

@testable import MomentMonitorCore

final class ProductDevCutoverRuntimeStatusReaderTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  func testExactCutoverSelectsAutonomousRuntimeWithoutFabricatedLegacyIdentity() async throws {
    let fixture = try self.makeFixture(runtimeOverrides: ["review_round": 8])
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let observation = await fixture.reader(now: self.now, processIsAlive: true).read(
      repository: .moment
    )

    XCTAssertEqual(observation.availability, .live)
    XCTAssertNil(observation.status)
    XCTAssertEqual(observation.autonomousStatus?.issueNumber, 381)
    XCTAssertEqual(observation.autonomousStatus?.phase, .reviewing)
    XCTAssertEqual(observation.autonomousStatus?.role, .reviewer)
    XCTAssertEqual(observation.autonomousStatus?.reviewRound, 8)
    XCTAssertEqual(observation.autonomousStatus?.repairAttempt, 1)
  }

  func testInvalidActivationUsesLegacyReaderWithoutImplicitCutover() async throws {
    let fixture = try self.makeFixture(engineOverrides: ["routing_mode": "unsafe"])
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let observation = await fixture.reader(now: self.now, processIsAlive: true).read(
      repository: .moment
    )

    XCTAssertEqual(observation.availability, .invalid)
    XCTAssertEqual(observation.message, "legacy fallback")
    XCTAssertNil(observation.autonomousStatus)
  }

  func testActivatedMissingOrUnsafeRuntimeFailsClosedWithoutLegacyFallback() async throws {
    let missing = try self.makeFixture(writeRuntime: false)
    defer { try? FileManager.default.removeItem(at: missing.directory) }
    var observation = await missing.reader(now: self.now, processIsAlive: true).read(
      repository: .moment
    )
    XCTAssertEqual(observation.availability, .invalid)
    XCTAssertTrue(observation.message?.contains("unavailable") == true)

    let unsafe = try self.makeFixture(runtimePermissions: 0o644)
    defer { try? FileManager.default.removeItem(at: unsafe.directory) }
    observation = await unsafe.reader(now: self.now, processIsAlive: true).read(
      repository: .moment
    )
    XCTAssertEqual(observation.availability, .invalid)
    XCTAssertTrue(observation.message?.contains("safely") == true)
  }

  func testAutonomousRuntimeUsesControllerLivenessAndKeepsTerminalTruth() async throws {
    let stale = try self.makeFixture()
    defer { try? FileManager.default.removeItem(at: stale.directory) }
    var observation = await stale.reader(now: self.now, processIsAlive: false).read(
      repository: .moment
    )
    XCTAssertEqual(observation.availability, .stale)
    XCTAssertEqual(observation.autonomousStatus?.phase, .reviewing)

    let terminal = try self.makeFixture(
      runtimeOverrides: ["phase": "completed", "role": "controller"]
    )
    defer { try? FileManager.default.removeItem(at: terminal.directory) }
    observation = await terminal.reader(now: self.now, processIsAlive: false).read(
      repository: .moment
    )
    XCTAssertEqual(observation.availability, .terminal)
    XCTAssertEqual(observation.autonomousStatus?.phase, .completed)
    XCTAssertTrue(observation.message?.contains("GitHub") == true)
  }

  func testMalformedAndRepositoryConflictingAutonomousEvidenceFailsClosed() async throws {
    let malformed = try self.makeFixture(runtimeOverrides: ["private_prompt": "reject"])
    defer { try? FileManager.default.removeItem(at: malformed.directory) }
    var observation = await malformed.reader(now: self.now, processIsAlive: true).read(
      repository: .moment
    )
    XCTAssertEqual(observation.availability, .invalid)
    XCTAssertNil(observation.autonomousStatus)

    let negativeRound = try self.makeFixture(runtimeOverrides: ["review_round": -1])
    defer { try? FileManager.default.removeItem(at: negativeRound.directory) }
    observation = await negativeRound.reader(now: self.now, processIsAlive: true).read(
      repository: .moment
    )
    XCTAssertEqual(observation.availability, .invalid)

    let nonIntegerRound = try self.makeFixture(runtimeOverrides: ["review_round": "8"])
    defer { try? FileManager.default.removeItem(at: nonIntegerRound.directory) }
    observation = await nonIntegerRound.reader(now: self.now, processIsAlive: true).read(
      repository: .moment
    )
    XCTAssertEqual(observation.availability, .invalid)

    let conflict = try self.makeFixture(runtimeOverrides: ["repository": "other/repository"])
    defer { try? FileManager.default.removeItem(at: conflict.directory) }
    observation = await conflict.reader(now: self.now, processIsAlive: true).read(
      repository: .moment
    )
    XCTAssertEqual(observation.availability, .invalid)
    XCTAssertTrue(observation.message?.contains("conflicts") == true)
  }

  func testAutonomousObservationBuildsRunningLaneAndSanitizedMobileSummary() throws {
    let status = ProductDevAutonomousRuntimeStatus(
      repository: RepositoryCoordinate.moment.fullName,
      issueNumber: 381,
      phase: .reviewing,
      role: .reviewer,
      headSHA: String(repeating: "e", count: 40),
      repairAttempt: 1,
      reviewRound: 2,
      observedAt: self.now.addingTimeInterval(-30)
    )
    let snapshot = MomentStateBuilder(now: self.now).build(
      configuration: MonitorConfiguration(),
      issues: [issue(381, title: "[M1] Autonomous work", labels: ["dev-running"])],
      pullRequests: [],
      workflowRuns: [],
      runtimeObservation: .autonomousLive(status)
    )

    XCTAssertEqual(snapshot.items(in: .running).map(\.issueNumber), [381])
    XCTAssertEqual(snapshot.items(in: .running).first?.statusText, "reviewer")
    XCTAssertNil(snapshot.items(in: .running).first?.automationDurationMilliseconds)
    let mobile = MobileRuntimeSummary(observation: snapshot.runtimeObservation, now: self.now)
    XCTAssertEqual(mobile.source, "productdev")
    XCTAssertEqual(mobile.autonomousPhase, .reviewing)
    XCTAssertEqual(mobile.phaseTitle, "Reviewing candidate")
    XCTAssertNil(mobile.pullRequestNumber)
    XCTAssertNil(mobile.issueDurationMilliseconds)
  }

  private func makeFixture(
    engineOverrides: [String: Any] = [:],
    runtimeOverrides: [String: Any] = [:],
    writeRuntime: Bool = true,
    runtimePermissions: Int = 0o600
  ) throws -> ProductDevCutoverFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "moment-monitor-productdev-cutover-\(UUID().uuidString)",
      isDirectory: true
    )
    let engineRuntime = directory.appendingPathComponent("EngineRuntime", isDirectory: true)
    let authority = engineRuntime.appendingPathComponent("current", isDirectory: true)
    let serviceEntry = authority.appendingPathComponent("Engine/productdev_runtime.py")
    let runtime = directory.appendingPathComponent("Profiles/moments-v2/runtime/current.json")
    let controllerPID = directory.appendingPathComponent(
      "MomentAutomation/moment-local-work.lock.d/pid")
    try FileManager.default.createDirectory(
      at: serviceEntry.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: runtime.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: controllerPID.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let generation = String(repeating: "a", count: 40)
    try self.writePrivateJSON(
      [
        "schema": "productdev.activation.v1",
        "generation": generation,
        "runtime_identity": generation,
        "authority_directory": authority.path,
        "service_entry": serviceEntry.path,
      ],
      to: directory.appendingPathComponent("activation.json")
    )
    var engine: [String: Any] = [
      "schema_version": 1,
      "profile_id": "moments-autonomous-v2",
      "profile_digest": "sha256:" + String(repeating: "b", count: 64),
      "authority_revision": generation,
      "moment_repository": RepositoryCoordinate.moment.fullName,
      "moment_main_revision": String(repeating: "c", count: 40),
      "moment_handoff_contract_digest": "sha256:" + String(repeating: "d", count: 64),
      "routing_mode": "recovery_first",
      "productdev_launchagent_unloaded": true,
    ]
    engine.merge(engineOverrides) { _, replacement in replacement }
    try self.writePrivateJSON(engine, to: engineRuntime.appendingPathComponent("activation.json"))

    if writeRuntime {
      var status: [String: Any] = [
        "schema_version": 1,
        "profile_id": "moments-autonomous-v2",
        "repository": RepositoryCoordinate.moment.fullName,
        "issue_number": 381,
        "phase": "reviewing",
        "role": "reviewer",
        "head_sha": String(repeating: "e", count: 40),
        "repair_attempt": 1,
        "review_round": 2,
        "observed_at": ISO8601DateFormatter().string(from: self.now.addingTimeInterval(-30)),
      ]
      status.merge(runtimeOverrides) { _, replacement in replacement }
      try self.writePrivateJSON(status, to: runtime, permissions: runtimePermissions)
    }
    try Data("4242\n".utf8).write(to: controllerPID)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644], ofItemAtPath: controllerPID.path)

    return ProductDevCutoverFixture(
      directory: directory,
      paths: ProductDevCutoverRuntimePaths(
        handoffActivation: directory.appendingPathComponent("activation.json"),
        engineActivation: engineRuntime.appendingPathComponent("activation.json"),
        authorityDirectory: authority,
        serviceEntry: serviceEntry,
        runtimeStatus: runtime,
        controllerPID: controllerPID
      )
    )
  }

  private func writePrivateJSON(
    _ object: [String: Any],
    to url: URL,
    permissions: Int = 0o600
  ) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    try FileManager.default.setAttributes(
      [.posixPermissions: permissions],
      ofItemAtPath: url.path
    )
  }
}

private struct ProductDevCutoverFixture {
  let directory: URL
  let paths: ProductDevCutoverRuntimePaths

  func reader(now: Date, processIsAlive: Bool) -> ProductDevCutoverRuntimeStatusReader {
    ProductDevCutoverRuntimeStatusReader(
      legacyReader: ProductDevLegacyReaderStub(),
      paths: self.paths,
      currentUserID: getuid(),
      processIsAlive: { _ in processIsAlive },
      now: { now }
    )
  }
}

private struct ProductDevLegacyReaderStub: AutomationRuntimeStatusReading {
  func read(repository: RepositoryCoordinate) async -> AutomationRuntimeObservation {
    .invalid("legacy fallback")
  }
}
