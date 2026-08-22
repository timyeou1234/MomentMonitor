import Foundation
import XCTest

@testable import MomentMonitorCore

final class GHExecutableLocatorTests: XCTestCase {
  func testExplicitExecutableWorksWithFinderStyleMinimalEnvironment() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("moment-monitor-locator-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("gh")
    XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )

    let located = try GHExecutableLocator.locate(environment: [
      "MOMENT_MONITOR_GH_PATH": executable.path,
      "PATH": "/usr/bin:/bin",
    ])

    XCTAssertEqual(located.standardizedFileURL, executable.standardizedFileURL)
  }
}
