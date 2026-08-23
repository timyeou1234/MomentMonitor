import XCTest
@testable import MomentMonitorCore

final class AutomationLifecycleStageTests: XCTestCase {
  func testRuntimePhasesMapToHumanReadableLifecycle() {
    XCTAssertEqual(AutomationRuntimePhase.preparingWorkspace.lifecycleStage, .implementing)
    XCTAssertEqual(AutomationRuntimePhase.lunaImplementation.lifecycleStage, .implementing)
    XCTAssertEqual(AutomationRuntimePhase.solHighUnblock.lifecycleStage, .implementing)

    XCTAssertEqual(AutomationRuntimePhase.prFast.lifecycleStage, .checking)
    XCTAssertEqual(AutomationRuntimePhase.solPRFastRepair.lifecycleStage, .checking)

    XCTAssertEqual(AutomationRuntimePhase.solReview.lifecycleStage, .reviewing)
    XCTAssertEqual(AutomationRuntimePhase.solReviewRepair.lifecycleStage, .reviewing)
    XCTAssertEqual(AutomationRuntimePhase.lunaVerification.lifecycleStage, .reviewing)

    XCTAssertEqual(AutomationRuntimePhase.publishingBranch.lifecycleStage, .publishing)
    XCTAssertEqual(AutomationRuntimePhase.verifyingExactHead.lifecycleStage, .publishing)

    XCTAssertEqual(AutomationRuntimePhase.mergingPR.lifecycleStage, .merging)
    XCTAssertEqual(AutomationRuntimePhase.closingIssue.lifecycleStage, .merging)

    XCTAssertEqual(AutomationRuntimePhase.completed.lifecycleStage, .completed)
    XCTAssertEqual(AutomationRuntimePhase.blocked.lifecycleStage, .completed)
    XCTAssertEqual(AutomationRuntimePhase.failed.lifecycleStage, .completed)
    XCTAssertEqual(AutomationRuntimePhase.stoppedNoChange.lifecycleStage, .completed)
  }

  func testLifecycleStagesHaveStablePresentationOrder() {
    XCTAssertEqual(
      AutomationLifecycleStage.allCases,
      [.implementing, .checking, .reviewing, .publishing, .merging, .completed]
    )
  }
}
