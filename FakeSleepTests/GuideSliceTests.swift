import Foundation
import XCTest
@testable import FakeSleep

final class LandingPresentationStoreTests: XCTestCase {
  func test완료버전이없으면온보딩을앱실행시에표시한다() {
    // Given: 비어 있는 독립 UserDefaults suite가 주입되어 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = LandingPresentationStore(defaults: defaults)

    // When: 앱 실행 시 온보딩 표시 여부를 읽는다.
    let shouldShowOnboarding = store.shouldShowOnboarding

    // Then: 완료 버전이 없으면 온보딩을 표시한다.
    XCTAssertTrue(shouldShowOnboarding)
  }

  func testlegacy표시안함값은온보딩자동표시정책에영향을주지않는다() {
    // Given: 이전 버전의 앱 실행 표시 안 함 값만 저장되어 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = LandingPresentationStore(defaults: defaults)

    // When: legacy 표시 안 함 값을 저장하고 새 저장소에서 정책을 읽는다.
    store.setShowsAtLaunch(false)
    let restoredStore = LandingPresentationStore(defaults: defaults)

    // Then: legacy 값은 호환성을 위해 읽히지만 새 온보딩은 표시한다.
    XCTAssertFalse(restoredStore.showsAtLaunch)
    XCTAssertTrue(restoredStore.shouldShowOnboarding)
  }

  func test온보딩버전1을완료하면새저장소에서도자동표시하지않는다() {
    // Given: 독립 UserDefaults suite에 연결된 저장소가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = LandingPresentationStore(defaults: defaults)

    // When: 온보딩 버전 1을 완료 처리하고 새 저장소에서 읽는다.
    store.markOnboardingCompleted(version: 1)
    let restoredStore = LandingPresentationStore(defaults: defaults)

    // Then: 버전 1 완료 사용자는 앱 실행 시 온보딩을 표시하지 않는다.
    XCTAssertFalse(restoredStore.shouldShowOnboarding)
    XCTAssertTrue(restoredStore.isOnboardingCompleted)
  }
}

final class KeyboardShortcutFormatterTests: XCTestCase {
  func test기본OptionCommandS를macOS기호로변환한다() {
    // Given: 기본 전역 단축키가 있다.
    let shortcut = KeyboardShortcut.defaultShortcut

    // When: 단축키 표시 문자열을 만든다.
    let string = KeyboardShortcutFormatter.string(from: shortcut)

    // Then: Option과 Command가 기호 순서로 표시된다.
    XCTAssertEqual(string, "⌥⌘S")
  }

  func test모든modifier를ControlOptionShiftCommand순서와keyname으로변환한다() {
    // Given: A 키에 모든 지원 modifier가 설정되어 있다.
    let shortcut = KeyboardShortcut(
      keyCode: 0,
      modifiers: [.control, .option, .shift, .command]
    )

    // When: 단축키 표시 문자열을 만든다.
    let string = KeyboardShortcutFormatter.string(from: shortcut)

    // Then: modifier는 고정 순서이고 뒤에 key name이 붙는다.
    XCTAssertEqual(string, "⌃⌥⇧⌘A")
  }
}
