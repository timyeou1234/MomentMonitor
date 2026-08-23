import XCTest

@testable import MomentMonitorCore

final class AutomationStrategyProgressTests: XCTestCase {
  func testSecondReviewShowsCompletedReviewAndCorrectionWithoutClaimingPass() throws {
    let status = runtimeStatus(
      issueNumber: 354,
      phase: .solReview,
      model: .sol,
      role: .reviewer,
      roundNumber: 2,
      totalRounds: 4,
      repairAttempt: 1
    )

    let progress = try XCTUnwrap(AutomationStrategyProgress(observation: .live(status)))

    XCTAssertEqual(progress.kind, .reviewLoop)
    XCTAssertEqual(progress.currentStepTitle, "Sol review 2 of 4")
    XCTAssertEqual(progress.steps.map(\.shortLabel), ["R1", "C1", "R2", "C2", "R3", "C3", "R4"])
    XCTAssertEqual(
      progress.steps.map(\.state),
      [.completed, .completed, .active, .pending, .pending, .pending, .pending]
    )
    XCTAssertFalse(progress.accessibilitySummary.localizedCaseInsensitiveContains("passed"))
  }

  func testFirstLunaCorrectionUsesAbsoluteRepairAttempt() throws {
    let status = runtimeStatus(
      issueNumber: 354,
      phase: .lunaImplementation,
      model: .luna,
      role: .implementer,
      roundNumber: 1,
      totalRounds: 3,
      repairAttempt: 1
    )

    let progress = try XCTUnwrap(AutomationStrategyProgress(observation: .live(status)))

    XCTAssertEqual(progress.currentStepTitle, "Luna correction 1 of 3")
    XCTAssertEqual(progress.steps[0].state, .completed)
    XCTAssertEqual(progress.steps[1].state, .active)
    XCTAssertEqual(progress.steps[2].state, .pending)
  }

  func testPRFastRepairGetsItsOwnValidationLoop() throws {
    let status = runtimeStatus(
      issueNumber: 354,
      phase: .solPRFastRepair,
      model: .sol,
      role: .repairer,
      roundNumber: 2,
      totalRounds: 3,
      repairAttempt: 2
    )

    let progress = try XCTUnwrap(AutomationStrategyProgress(observation: .live(status)))

    XCTAssertEqual(progress.kind, .validationLoop)
    XCTAssertEqual(progress.title, "PR Fast loop")
    XCTAssertEqual(progress.currentStepTitle, "Sol correction 2 of 3")
    XCTAssertEqual(progress.steps.map(\.shortLabel), ["V1", "C1", "V2", "C2", "V3", "C3", "V4"])
    XCTAssertEqual(progress.steps[3].state, .active)
  }

  func testFinalSolHighDoesNotInventAFinitePercentage() throws {
    let status = runtimeStatus(
      issueNumber: 61,
      phase: .solHighUnblock,
      model: .sol,
      role: .repairer
    )

    let progress = try XCTUnwrap(AutomationStrategyProgress(observation: .live(status)))

    XCTAssertEqual(progress.kind, .finalSolHigh)
    XCTAssertEqual(progress.currentStepTitle, "Until pass or a terminal boundary")
    XCTAssertEqual(progress.steps.map(\.shortLabel), ["HIGH"])
    XCTAssertEqual(progress.steps.map(\.state), [.active])
  }

  func testStaleLoopMarksTheCurrentCheckpointHalted() throws {
    let status = runtimeStatus(
      issueNumber: 354,
      phase: .solReview,
      model: .sol,
      role: .reviewer,
      roundNumber: 3,
      totalRounds: 4,
      repairAttempt: 2
    )
    let observation = AutomationRuntimeObservation.stale(
      status,
      message: "The controller process is no longer running."
    )

    let progress = try XCTUnwrap(AutomationStrategyProgress(observation: observation))

    XCTAssertEqual(progress.steps[4].state, .halted)
    XCTAssertEqual(progress.steps[5].state, .pending)
  }
}
