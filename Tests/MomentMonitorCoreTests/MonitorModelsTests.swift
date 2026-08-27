import XCTest

@testable import MomentMonitorCore

final class MonitorModelsTests: XCTestCase {
  func testTerminalRuntimeYieldsCurrentPresentationToDifferentRunningIssue() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let terminal = ProductDevAutonomousRuntimeStatus(
      repository: RepositoryCoordinate.moment.fullName,
      issueNumber: 381,
      phase: .completed,
      role: .controller,
      headSHA: String(repeating: "a", count: 40),
      repairAttempt: 3,
      reviewRound: 11,
      observedAt: now
    )
    let current = MonitorItem(
      id: "running:70",
      lane: .running,
      source: .inferredState,
      title: "#70 Current",
      detail: "Local runtime pending",
      issueNumber: 70,
      url: URL(string: "https://github.com/example/repo/issues/70")!,
      updatedAt: now,
      severity: .active
    )
    let snapshot = MomentMonitorSnapshot(
      repository: .moment,
      generatedAt: now,
      items: [current],
      runtimeObservation: .autonomousTerminal(terminal)
    )

    XCTAssertEqual(snapshot.rolloverCurrentAutomationItem?.issueNumber, 70)
    XCTAssertEqual(snapshot.runtimeObservation.autonomousStatus?.issueNumber, 381)
    XCTAssertEqual(snapshot.runtimeObservation.autonomousStatus?.reviewRound, 11)
  }

  func testLiveRuntimeAndMatchingTerminalDoNotCreateRolloverProjection() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let running = MonitorItem(
      id: "running:381",
      lane: .running,
      source: .inferredState,
      title: "#381 Running",
      detail: "Running",
      issueNumber: 381,
      url: URL(string: "https://github.com/example/repo/issues/381")!,
      updatedAt: now,
      severity: .active
    )
    let terminal = ProductDevAutonomousRuntimeStatus(
      repository: RepositoryCoordinate.moment.fullName,
      issueNumber: 381,
      phase: .completed,
      role: .controller,
      headSHA: String(repeating: "a", count: 40),
      repairAttempt: 3,
      reviewRound: 11,
      observedAt: now
    )
    let terminalSnapshot = MomentMonitorSnapshot(
      repository: .moment,
      generatedAt: now,
      items: [running],
      runtimeObservation: .autonomousTerminal(terminal)
    )
    let live = ProductDevAutonomousRuntimeStatus(
      repository: RepositoryCoordinate.moment.fullName,
      issueNumber: 381,
      phase: .reviewing,
      role: .reviewer,
      headSHA: String(repeating: "a", count: 40),
      repairAttempt: 3,
      reviewRound: 11,
      observedAt: now
    )
    let liveSnapshot = MomentMonitorSnapshot(
      repository: .moment,
      generatedAt: now,
      items: [running],
      runtimeObservation: .autonomousLive(live)
    )

    XCTAssertNil(terminalSnapshot.rolloverCurrentAutomationItem)
    XCTAssertNil(liveSnapshot.rolloverCurrentAutomationItem)
  }
}
