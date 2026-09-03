import XCTest
@testable import FakeSleep

final class FakeSleepTests: XCTestCase {
  @MainActor
  func testAppContainerCanBeCreated() {
    XCTAssertNotNil(AppContainer())
  }
}
