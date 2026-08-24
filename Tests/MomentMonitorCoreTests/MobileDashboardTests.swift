import Foundation
import XCTest

@testable import MomentMonitorCore

final class MobileDashboardTests: XCTestCase {
  func testEnvelopePublishesDisplayStateWithoutLocalProcessIdentity() throws {
    let activityDate = fixedDate("2026-08-22T07:00:00Z")
    let activity = AutomationRuntimeActivity(
      schemaVersion: 1,
      source: .appServer,
      sequence: 2,
      kind: .command,
      state: .completed,
      action: .test,
      observedAt: activityDate,
      completedCommands: 1,
      failedCommands: 0,
      completedFileChanges: 0,
      completedTools: 0,
      recent: [
        AutomationActivityEvent(
          sequence: 2,
          kind: .command,
          state: .completed,
          action: .test,
          observedAt: activityDate
        )
      ]
    )
    let status = runtimeStatus(
      issueNumber: 237,
      phase: .solReview,
      outcome: .active,
      model: .sol,
      role: .reviewer,
      roundNumber: 2,
      totalRounds: 4,
      activity: activity
    )
    let snapshot = MomentMonitorSnapshot(
      repository: .moment,
      generatedAt: fixedDate("2026-08-22T07:00:00Z"),
      items: [
        MonitorItem(
          id: "running:runtime:\(status.runID)",
          lane: .running,
          source: .inferredState,
          title: "#237 Backend AI gateway",
          detail: "Sol review · round 2 of 4",
          statusText: "SOL · 2/4",
          issueNumber: 237,
          url: URL(string: "https://github.com/timyeou1234/Moment/issues/237")!,
          updatedAt: status.updatedAt,
          severity: .active
        )
      ],
      projectProgress: ProjectProgress(completedCount: 3, totalCount: 8),
      runtimeObservation: .live(status)
    )
    let codexUsage = CodexUsageObservation(
      availability: .live,
      planType: "pro",
      primary: CodexUsageWindow(
        usedPercent: 38,
        windowDurationMinutes: 10_080,
        resetsAt: fixedDate("2026-08-28T03:19:49Z")
      ),
      fetchedAt: fixedDate("2026-08-22T07:00:00Z")
    )
    let store = MobileDashboardSnapshotStore(snapshot: snapshot, codexUsage: codexUsage)

    let data = try store.encodedSnapshot(servedAt: fixedDate("2026-08-22T07:00:01Z"))
    let decoded = try JSONDecoder.mobileDashboard.decode(MobileDashboardEnvelope.self, from: data)
    let rendered = String(decoding: data, as: UTF8.self)

    XCTAssertEqual(decoded.schemaVersion, 3)
    XCTAssertEqual(decoded.repository, "timyeou1234/Moment")
    XCTAssertEqual(decoded.runtime.phase, .solReview)
    XCTAssertEqual(decoded.runtime.activeStage, .review)
    XCTAssertEqual(decoded.runtime.roundNumber, 2)
    XCTAssertEqual(decoded.runtime.strategy?.kind, .reviewLoop)
    XCTAssertEqual(decoded.runtime.activity?.source, .appServer)
    XCTAssertEqual(decoded.runtime.activity?.action, .test)
    XCTAssertEqual(
      decoded.runtime.strategy?.steps.map(\.shortLabel), ["R1", "C1", "R2", "C2", "R3", "C3", "R4"])
    XCTAssertTrue(rendered.contains("\"activeStage\":3"))
    XCTAssertEqual(decoded.codexUsage.primary?.remainingPercent, 62)
    XCTAssertEqual(decoded.lanes.first?.items.first?.issueNumber, 237)
    XCTAssertFalse(rendered.contains(status.runID))
    XCTAssertFalse(rendered.contains("runnerPID"))
    XCTAssertFalse(rendered.contains("baseSHA"))
    XCTAssertFalse(rendered.contains("headSHA"))
    XCTAssertFalse(rendered.contains(String(status.runnerPID)))
    XCTAssertFalse(rendered.contains("planType"))
    XCTAssertFalse(rendered.contains("lifetimeTokens"))

    let oldActivityEnvelope = MobileDashboardEnvelope(
      snapshot: snapshot,
      codexUsage: codexUsage,
      servedAt: fixedDate("2026-08-22T07:02:01Z")
    )
    XCTAssertNil(oldActivityEnvelope.runtime.activity)
  }

  func testBundledDashboardIsMobileFirstAndUsesNoExternalAssets() throws {
    let assets = try MobileDashboardAssets.bundled()
    let html = String(decoding: assets.indexHTML, as: UTF8.self)
    let css = String(decoding: assets.stylesheet, as: UTF8.self)
    let javascript = String(decoding: assets.javascript, as: UTF8.self)

    XCTAssertTrue(html.contains("width=device-width"))
    XCTAssertTrue(html.contains("apple-mobile-web-app-capable"))
    XCTAssertTrue(html.contains("READ ONLY"))
    XCTAssertTrue(html.contains("CODEX CAPACITY"))
    XCTAssertTrue(html.contains("id=\"refresh-button\""))
    XCTAssertTrue(html.contains("id=\"last-update-time\""))
    XCTAssertTrue(html.contains("id=\"runtime-activity\""))
    XCTAssertTrue(css.contains("env(safe-area-inset-top)"))
    XCTAssertTrue(css.contains("@media (min-width: 680px)"))
    XCTAssertTrue(javascript.contains("/api/v1/snapshot"))
    XCTAssertTrue(javascript.contains("renderCodexUsage"))
    XCTAssertTrue(javascript.contains("usage?.availability === \"stale\""))
    XCTAssertTrue(javascript.contains("renderStrategy"))
    XCTAssertTrue(javascript.contains("renderActivity"))
    XCTAssertTrue(javascript.contains("activityTitle"))
    XCTAssertTrue(javascript.contains("latestDataUpdate"))
    XCTAssertTrue(javascript.contains("poll({ manual: true })"))
    XCTAssertTrue(javascript.contains("const stageOrder = [0, 1, 2, 3, 4]"))
    XCTAssertTrue(javascript.contains("snapshot.schemaVersion !== 3"))
    XCTAssertTrue(javascript.contains("textContent"))
    XCTAssertFalse(html.contains("https://"))
    XCTAssertFalse(css.contains("url(http"))
    XCTAssertFalse(javascript.contains("innerHTML"))
    XCTAssertFalse(javascript.contains("localStorage"))
  }

  func testEnvelopeDoesNotPublishAnOldCapacityAsLive() throws {
    let snapshot = MomentMonitorSnapshot.empty(
      repository: .moment,
      at: fixedDate("2026-08-24T02:04:00Z")
    )
    let usage = CodexUsageObservation(
      availability: .live,
      primary: CodexUsageWindow(
        usedPercent: 44,
        windowDurationMinutes: 10_080,
        resetsAt: fixedDate("2026-08-28T01:59:49Z")
      ),
      fetchedAt: fixedDate("2026-08-24T02:00:00Z")
    )

    let envelope = MobileDashboardEnvelope(
      snapshot: snapshot,
      codexUsage: usage,
      servedAt: fixedDate("2026-08-24T02:04:00Z")
    )

    XCTAssertEqual(envelope.codexUsage.availability, .stale)
    XCTAssertNil(envelope.codexUsage.primary)
    XCTAssertEqual(envelope.codexUsage.fetchedAt, fixedDate("2026-08-24T02:00:00Z"))
    XCTAssertEqual(
      envelope.codexUsage.message,
      "Codex capacity has not refreshed recently."
    )
  }

  #if os(macOS)
    func testLoopbackServerReturnsSnapshotAndSecurityHeaders() async throws {
      let snapshot = MomentMonitorSnapshot(
        repository: .moment,
        generatedAt: fixedDate("2026-08-22T07:00:00Z"),
        items: [],
        projectProgress: ProjectProgress(completedCount: 3, totalCount: 8)
      )
      let store = MobileDashboardSnapshotStore(snapshot: snapshot)
      let recorder = MobileDashboardStateRecorder()
      let server = try MobileDashboardServer(snapshotStore: store) { state in
        recorder.record(state)
      }
      defer { server.stop() }

      try server.start(port: 0)
      let port = try recorder.waitForReadyPort()
      let configuration = URLSessionConfiguration.ephemeral
      configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
      let session = URLSession(configuration: configuration)

      let (data, rawResponse) = try await session.data(
        from: URL(string: "http://127.0.0.1:\(port)/api/v1/snapshot")!
      )
      let response = try XCTUnwrap(rawResponse as? HTTPURLResponse)
      let envelope = try JSONDecoder.mobileDashboard.decode(
        MobileDashboardEnvelope.self,
        from: data
      )

      XCTAssertEqual(response.statusCode, 200)
      XCTAssertEqual(response.value(forHTTPHeaderField: "Cache-Control"), "no-store, max-age=0")
      XCTAssertEqual(response.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff")
      XCTAssertEqual(response.value(forHTTPHeaderField: "X-Frame-Options"), "DENY")
      XCTAssertTrue(
        response.value(forHTTPHeaderField: "Content-Security-Policy")?.contains(
          "frame-ancestors 'none'") == true
      )
      XCTAssertNil(response.value(forHTTPHeaderField: "Access-Control-Allow-Origin"))
      XCTAssertEqual(envelope.projectProgress.completedCount, 3)

      let (html, htmlRawResponse) = try await session.data(
        from: URL(string: "http://127.0.0.1:\(port)/")!
      )
      XCTAssertEqual((htmlRawResponse as? HTTPURLResponse)?.statusCode, 200)
      XCTAssertTrue(String(decoding: html, as: UTF8.self).contains("Moment Monitor"))
    }

    func testLoopbackServerRejectsMutatingMethodsAndUntrustedHosts() async throws {
      let store = MobileDashboardSnapshotStore(snapshot: .empty(repository: .moment))
      let recorder = MobileDashboardStateRecorder()
      let server = try MobileDashboardServer(snapshotStore: store) { state in
        recorder.record(state)
      }
      defer { server.stop() }

      try server.start(port: 0)
      let port = try recorder.waitForReadyPort()
      let session = URLSession(configuration: .ephemeral)
      var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/v1/snapshot")!)
      request.httpMethod = "POST"
      let (_, rawResponse) = try await session.data(for: request)
      XCTAssertEqual((rawResponse as? HTTPURLResponse)?.statusCode, 405)
      XCTAssertEqual(
        (rawResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Allow"),
        "GET, HEAD"
      )

      let response = try await RawHTTPClient.request(
        port: port,
        value: "GET /api/v1/snapshot HTTP/1.1\r\nHost: attacker.example\r\n\r\n"
      )
      XCTAssertTrue(response.hasPrefix("HTTP/1.1 403 Forbidden"))
    }
  #endif
}

extension JSONDecoder {
  fileprivate static var mobileDashboard: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

#if os(macOS)
  import Network

  private final class MobileDashboardStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var port: Int?
    private var failure: String?

    func record(_ state: MobileDashboardServerState) {
      self.lock.withLock {
        switch state {
        case .ready(let port): self.port = port
        case .failed(let message): self.failure = message
        default: return
        }
        self.semaphore.signal()
      }
    }

    func waitForReadyPort() throws -> Int {
      guard self.semaphore.wait(timeout: .now() + 3) == .success else {
        throw NSError(
          domain: "MobileDashboardTests",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for dashboard server"]
        )
      }
      return try self.lock.withLock {
        if let port { return port }
        throw NSError(
          domain: "MobileDashboardTests",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: self.failure ?? "Dashboard server failed"]
        )
      }
    }
  }

  private enum RawHTTPClient {
    static func request(port: Int, value: String) async throws -> String {
      try await withCheckedThrowingContinuation { continuation in
        let connection = NWConnection(
          host: NWEndpoint.Host("127.0.0.1"),
          port: NWEndpoint.Port(rawValue: UInt16(port))!,
          using: .tcp
        )
        let queue = DispatchQueue(label: "MobileDashboardTests.raw-http")
        connection.stateUpdateHandler = { state in
          switch state {
          case .ready:
            connection.send(
              content: Data(value.utf8),
              completion: .contentProcessed { error in
                if let error {
                  connection.cancel()
                  continuation.resume(throwing: error)
                  return
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_535) {
                  data, _, _, error in
                  connection.cancel()
                  if let error {
                    continuation.resume(throwing: error)
                  } else {
                    continuation.resume(returning: String(decoding: data ?? Data(), as: UTF8.self))
                  }
                }
              })
          case .failed(let error):
            connection.cancel()
            continuation.resume(throwing: error)
          default:
            break
          }
        }
        connection.start(queue: queue)
      }
    }
  }
#endif
