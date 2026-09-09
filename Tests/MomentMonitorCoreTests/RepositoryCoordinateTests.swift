import XCTest

@testable import MomentMonitorCore

final class RepositoryCoordinateTests: XCTestCase {
  func testParsesAndNormalizesOwnerName() throws {
    let coordinate = try RepositoryCoordinate(parsing: "  timyeou1234/Moment  ")
    XCTAssertEqual(coordinate.fullName, "timyeou1234/Moment")
  }

  func testRejectsMissingOrAdditionalPathSegments() {
    XCTAssertThrowsError(try RepositoryCoordinate(parsing: "Moment"))
    XCTAssertThrowsError(try RepositoryCoordinate(parsing: "timyeou1234/Moment/issues"))
    XCTAssertThrowsError(try RepositoryCoordinate(parsing: "../Moment"))
  }

  func testInvalidPersistedRepositoryResolvesToDisplayedFallback() {
    let repository = RepositoryCoordinate.resolvingPersisted("not-a-repository")

    XCTAssertEqual(repository, .moment)
    XCTAssertEqual(repository.fullName, "timyeou1234/Moment")
  }

  func testSettingsDraftDoesNotDriveLiveRepositoryPresentationOrNavigation() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let menuSource = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/MomentMonitor/MonitorMenuView.swift"),
      encoding: .utf8
    )
    let settingsSource = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/MomentMonitor/MonitorSettingsView.swift"),
      encoding: .utf8
    )
    let storeSource = try String(
      contentsOf: repositoryRoot.appendingPathComponent("Sources/MomentMonitor/MonitorStore.swift"),
      encoding: .utf8
    )

    XCTAssertTrue(menuSource.contains("Text(self.store.appliedRepositoryText)"))
    XCTAssertFalse(menuSource.contains("repositoryDraftText"))
    XCTAssertTrue(settingsSource.contains("text: self.$store.repositoryDraftText"))
    XCTAssertTrue(
      storeSource.contains(
        "URL(string: \"https://github.com/\\(self.configuredRepository.fullName)\")"
      )
    )
  }
}
