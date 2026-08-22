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
}
