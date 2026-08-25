import Foundation
import XCTest

@testable import MomentMonitorCore

final class DevelopmentObserverTests: XCTestCase {
  private let now = fixedDate("2026-08-25T08:00:00Z")

  func testPayloadContainsOnlyClosedObservationFields() throws {
    let snapshot = self.snapshot(
      items: [
        self.item(
          issueNumber: 436,
          lane: .blocked,
          title: "SECRET issue title",
          detail: "SECRET raw review finding",
          statusText: "auto recovery"
        )
      ]
    )

    let payload = DevelopmentObservationPayload(snapshot: snapshot)
    let data = try JSONEncoder().encode(payload)
    let encoded = String(decoding: data, as: UTF8.self)

    XCTAssertEqual(payload.items.map(\.state), [.autoRecovery])
    XCTAssertFalse(encoded.contains("SECRET"))
    XCTAssertFalse(encoded.contains("title"))
    XCTAssertFalse(encoded.contains("detail"))
    XCTAssertFalse(encoded.contains("url"))
    XCTAssertFalse(encoded.contains("updated"))
    XCTAssertFalse(encoded.contains("body"))
    XCTAssertFalse(encoded.contains("comment"))
  }

  func testDeterministicAssessmentDistinguishesRecoveryOwnerAndPlainBlock() {
    let autoRecovery = DevelopmentObservationAssessment(
      snapshot: self.snapshot(items: [self.item(issueNumber: 436, statusText: "auto recovery")])
    )
    XCTAssertEqual(autoRecovery.classification, .blockedTechnical)
    XCTAssertEqual(autoRecovery.recommendation, .keepWatching)
    XCTAssertEqual(autoRecovery.issueNumber, 436)

    let plainBlock = DevelopmentObservationAssessment(
      snapshot: self.snapshot(items: [self.item(issueNumber: 500, statusText: "blocked")])
    )
    XCTAssertEqual(plainBlock.classification, .blockedTechnical)
    XCTAssertEqual(plainBlock.recommendation, .recommendCodexDiagnosis)

    let ownerDecision = DevelopmentObservationAssessment(
      snapshot: self.snapshot(items: [self.item(issueNumber: 501, statusText: "owner decision")])
    )
    XCTAssertEqual(ownerDecision.classification, .needsOwner)
    XCTAssertEqual(ownerDecision.recommendation, .notifyOwner)
  }

  func testStaleRuntimeFailsClosedWithoutInventingARepair() {
    let status = runtimeStatus(issueNumber: 451)
    let assessment = DevelopmentObservationAssessment(
      snapshot: self.snapshot(
        items: [],
        runtime: .stale(status, message: "Runner is not live.")
      )
    )

    XCTAssertEqual(assessment.classification, .stale)
    XCTAssertEqual(assessment.recommendation, .notifyOwner)
    XCTAssertEqual(assessment.issueNumber, 451)
  }

  func testStaleRuntimeOutranksAnAutomaticRecoveryPresentation() {
    let status = runtimeStatus(issueNumber: 436, phase: .solHighUnblock)
    let assessment = DevelopmentObservationAssessment(
      snapshot: self.snapshot(
        items: [self.item(issueNumber: 436, statusText: "auto recovery")],
        runtime: .stale(status, message: "Runner is not live.")
      )
    )

    XCTAssertEqual(assessment.classification, .stale)
    XCTAssertEqual(assessment.recommendation, .notifyOwner)
    XCTAssertEqual(assessment.issueNumber, 436)
  }

  func testFingerprintIgnoresTitlesDetailsTimesAndFreeformRuntimeActivity() {
    let first = self.snapshot(
      generatedAt: fixedDate("2026-08-25T08:00:00Z"),
      items: [
        self.item(
          issueNumber: 436,
          title: "First title",
          detail: "First detail",
          statusText: "auto recovery",
          updatedAt: fixedDate("2026-08-25T07:00:00Z")
        )
      ]
    )
    let second = self.snapshot(
      generatedAt: fixedDate("2026-08-25T08:10:00Z"),
      items: [
        self.item(
          issueNumber: 436,
          title: "Changed title",
          detail: "Changed detail",
          statusText: "auto recovery",
          updatedAt: fixedDate("2026-08-25T08:09:00Z")
        )
      ]
    )

    XCTAssertEqual(
      DevelopmentObservationPayload(snapshot: first).fingerprint,
      DevelopmentObservationPayload(snapshot: second).fingerprint
    )
  }

  func testObserverCallsModelOnceForAnUnchangedFingerprint() async {
    let model = CountingDevelopmentModel()
    let observer = DevelopmentObserver(modelClient: model)
    let snapshot = self.snapshot(items: [self.item(issueNumber: 436, statusText: "auto recovery")])

    let first = await observer.observe(snapshot: snapshot, localModelEnabled: true, at: self.now)
    let second = await observer.observe(
      snapshot: snapshot,
      localModelEnabled: true,
      at: self.now.addingTimeInterval(60)
    )

    XCTAssertEqual(first.source, .ollama)
    XCTAssertEqual(first, second)
    let callCount = await model.callCount()
    XCTAssertEqual(callCount, 1)
  }

  func testModelCannotEscalateTheDeterministicRecommendation() async {
    let model = MismatchingDevelopmentModel()
    let observer = DevelopmentObserver(modelClient: model)
    let snapshot = self.snapshot(items: [self.item(issueNumber: 436, statusText: "auto recovery")])

    let diagnosis = await observer.observe(
      snapshot: snapshot,
      localModelEnabled: true,
      at: self.now
    )

    XCTAssertEqual(diagnosis.source, .deterministic)
    XCTAssertEqual(diagnosis.classification, .blockedTechnical)
    XCTAssertEqual(diagnosis.recommendation, .keepWatching)
  }

  func testLoopbackEndpointValidationRejectsLANAndCredentials() {
    XCTAssertTrue(
      OllamaDevelopmentObserverClient.isPermittedLoopbackEndpoint(
        URL(string: "http://127.0.0.1:11434")!
      ))
    XCTAssertTrue(
      OllamaDevelopmentObserverClient.isPermittedLoopbackEndpoint(
        URL(string: "http://[::1]:11434/")!
      ))
    XCTAssertFalse(
      OllamaDevelopmentObserverClient.isPermittedLoopbackEndpoint(
        URL(string: "http://192.168.1.20:11434")!
      ))
    XCTAssertFalse(
      OllamaDevelopmentObserverClient.isPermittedLoopbackEndpoint(
        URL(string: "https://127.0.0.1:11434")!
      ))
    XCTAssertFalse(
      OllamaDevelopmentObserverClient.isPermittedLoopbackEndpoint(
        URL(string: "http://user:pass@127.0.0.1:11434")!
      ))
  }

  func testOllamaRequestDisablesThinkingAndRetainedSessionWithoutFreeformState() throws {
    let client = try OllamaDevelopmentObserverClient(
      endpoint: URL(string: "http://127.0.0.1:11434")!
    )
    let assessment = DevelopmentObservationAssessment(
      snapshot: self.snapshot(
        items: [
          self.item(
            issueNumber: 436,
            title: "SECRET title",
            detail: "SECRET finding",
            statusText: "auto recovery"
          )
        ]
      )
    )

    let request = try client.makeRequest(assessment: assessment)
    let body = try XCTUnwrap(request.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/api/chat")
    XCTAssertEqual(json["model"] as? String, "qwen3.5:27b")
    XCTAssertEqual(json["think"] as? Bool, false)
    XCTAssertEqual(json["stream"] as? Bool, false)
    XCTAssertEqual(json["keep_alive"] as? String, "0s")
    XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("SECRET"))
  }

  func testStrictOllamaResponseAcceptsOnlyMatchingBoundedDecision() throws {
    let assessment = DevelopmentObservationAssessment(
      snapshot: self.snapshot(items: [self.item(issueNumber: 436, statusText: "auto recovery")])
    )
    let content =
      #"{"classification":"blocked_technical","recommendation":"keep_watching","summary":"Issue #436 已由既有 Codex 恢復流程接手，持續觀察即可。"}"#
    let response = try JSONSerialization.data(withJSONObject: [
      "message": ["role": "assistant", "content": content],
      "done": true,
      "done_reason": "stop",
    ])

    let decoded = try OllamaDevelopmentObserverClient.decodeResponse(
      response,
      assessment: assessment
    )

    XCTAssertEqual(decoded.classification, .blockedTechnical)
    XCTAssertEqual(decoded.recommendation, .keepWatching)
    XCTAssertTrue(decoded.summary.contains("#436"))

    let extraKeyContent =
      #"{"classification":"blocked_technical","recommendation":"keep_watching","summary":"watch","dispatch":true}"#
    let invalid = try JSONSerialization.data(withJSONObject: [
      "message": ["role": "assistant", "content": extraKeyContent],
      "done": true,
    ])
    XCTAssertThrowsError(
      try OllamaDevelopmentObserverClient.decodeResponse(invalid, assessment: assessment)
    )
  }

  private func snapshot(
    generatedAt: Date? = nil,
    items: [MonitorItem],
    runtime: AutomationRuntimeObservation = .absent
  ) -> MomentMonitorSnapshot {
    MomentMonitorSnapshot(
      repository: .moment,
      generatedAt: generatedAt ?? self.now,
      items: items,
      runtimeObservation: runtime
    )
  }

  private func item(
    issueNumber: Int,
    lane: MonitorLane = .blocked,
    title: String = "Issue",
    detail: String = "Detail",
    statusText: String,
    updatedAt: Date? = nil
  ) -> MonitorItem {
    MonitorItem(
      id: "\(lane.rawValue):issue:\(issueNumber)",
      lane: lane,
      source: .issue,
      title: title,
      detail: detail,
      statusText: statusText,
      issueNumber: issueNumber,
      url: URL(string: "https://github.com/timyeou1234/Moment/issues/\(issueNumber)")!,
      updatedAt: updatedAt ?? self.now,
      severity: lane == .blocked ? .warning : .normal,
      sequenceNumber: issueNumber
    )
  }
}

private actor CountingDevelopmentModel: DevelopmentObserverModelCalling {
  private var calls = 0

  func diagnose(assessment: DevelopmentObservationAssessment) async throws
    -> DevelopmentModelDiagnosis
  {
    self.calls += 1
    return DevelopmentModelDiagnosis(
      classification: assessment.classification,
      recommendation: assessment.recommendation,
      summary: "本地模型摘要"
    )
  }

  func callCount() -> Int { self.calls }
}

private struct MismatchingDevelopmentModel: DevelopmentObserverModelCalling {
  func diagnose(assessment _: DevelopmentObservationAssessment) async throws
    -> DevelopmentModelDiagnosis
  {
    DevelopmentModelDiagnosis(
      classification: .healthy,
      recommendation: .none,
      summary: "Unsafe escalation"
    )
  }
}
