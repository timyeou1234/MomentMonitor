import Darwin
import Foundation
import XCTest

@testable import MomentMonitorCore

final class OxAuditStatusReaderTests: XCTestCase {
  func testReadsStrictCurrentProgress() async throws {
    try await self.withStatusFile { fileURL in
      try self.writeStatus(to: fileURL)
      let reader = OxAuditStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        now: { fixedDate("2026-08-24T15:05:00Z") }
      )

      let observation = await reader.read()

      XCTAssertEqual(observation.availability, .current)
      XCTAssertEqual(observation.status?.state, .backoff)
      XCTAssertEqual(observation.status?.currentIssue, 436)
      XCTAssertEqual(observation.status?.completedCount, 1)
      XCTAssertEqual(observation.status?.totalCount, 21)
      XCTAssertEqual(observation.status?.lastHTTPStatus, 503)
    }
  }

  func testRejectsUnknownFieldsAndBroadPermissions() async throws {
    try await self.withStatusFile { fileURL in
      try self.writeStatus(to: fileURL, overrides: ["token_count": 133])
      var reader = OxAuditStatusReader(fileURL: fileURL, currentUserID: getuid())
      var observation = await reader.read()
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("outside the public contract") == true)

      try self.writeStatus(to: fileURL)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
      reader = OxAuditStatusReader(fileURL: fileURL, currentUserID: getuid())
      observation = await reader.read()
      XCTAssertEqual(observation.availability, .invalid)
      XCTAssertTrue(observation.message?.contains("permissions") == true)
    }
  }

  func testOldNonterminalStatusBecomesStaleButTerminalStatusRemainsCurrent() async throws {
    try await self.withStatusFile { fileURL in
      try self.writeStatus(to: fileURL)
      var reader = OxAuditStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        now: { fixedDate("2026-08-24T16:00:01Z") }
      )
      var observation = await reader.read()
      XCTAssertEqual(observation.availability, .stale)

      try self.writeStatus(
        to: fileURL,
        overrides: [
          "state": "completed", "current_issue": NSNull(),
          "completed_count": 21, "next_attempt_at": NSNull(),
        ]
      )
      reader = OxAuditStatusReader(
        fileURL: fileURL,
        currentUserID: getuid(),
        now: { fixedDate("2026-08-25T15:00:00Z") }
      )
      observation = await reader.read()
      XCTAssertEqual(observation.availability, .current)
      XCTAssertEqual(observation.status?.state, .completed)
    }
  }

  private func withStatusFile(
    _ body: (URL) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ox-audit-reader-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory.appendingPathComponent("ox-current.json"))
  }

  private func writeStatus(to url: URL, overrides: [String: Any] = [:]) throws {
    var value: [String: Any] = [
      "schema_version": 1,
      "format_version": "moment.ox-audit.v1",
      "model": "Ox Alpha Free",
      "state": "backoff",
      "current_issue": 436,
      "completed_count": 1,
      "total_count": 21,
      "last_http_status": 503,
      "updated_at": "2026-08-24T15:00:00.000Z",
      "next_attempt_at": "2026-08-24T15:10:00.000Z",
    ]
    for (key, replacement) in overrides { value[key] = replacement }
    try JSONSerialization.data(withJSONObject: value).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
