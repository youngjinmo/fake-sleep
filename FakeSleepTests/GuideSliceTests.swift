import Foundation
import XCTest
@testable import FakeSleep

final class LandingPresentationStoreTests: XCTestCase {
  func test저장된값이없으면앱실행시표시한다() {
    // Given: 비어 있는 독립 UserDefaults suite가 주입되어 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = LandingPresentationStore(defaults: defaults)

    // When: 앱 실행 시 안내 표시 여부를 읽는다.
    let showsAtLaunch = store.showsAtLaunch

    // Then: 저장된 값이 없으면 안내를 표시한다.
    XCTAssertTrue(showsAtLaunch)
  }

  func test앱실행시표시여부를끄고켜면새저장소에서도값을읽는다() {
    // Given: 독립 UserDefaults suite에 연결된 저장소가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = LandingPresentationStore(defaults: defaults)

    // When: 앱 실행 시 표시 여부를 차례로 끄고 켠다.
    store.setShowsAtLaunch(false)
    let hiddenStore = LandingPresentationStore(defaults: defaults)
    let hiddenValue = hiddenStore.showsAtLaunch
    store.setShowsAtLaunch(true)
    let shownStore = LandingPresentationStore(defaults: defaults)

    // Then: 각 설정이 UserDefaults에 저장되고 다시 읽힌다.
    XCTAssertFalse(hiddenValue)
    XCTAssertTrue(shownStore.showsAtLaunch)
  }

  func test서로다른UserDefaultssuite의앱실행시표시여부를격리한다() {
    // Given: 서로 다른 UUID suite에 연결된 두 저장소가 있다.
    let firstDefaults = UserDefaults(suiteName: UUID().uuidString)!
    let secondDefaults = UserDefaults(suiteName: UUID().uuidString)!
    let firstStore = LandingPresentationStore(defaults: firstDefaults)
    let secondStore = LandingPresentationStore(defaults: secondDefaults)

    // When: 첫 번째 suite에서만 앱 실행 시 표시를 끈다.
    firstStore.setShowsAtLaunch(false)

    // Then: 두 번째 suite의 기본 표시 설정에는 영향을 주지 않는다.
    XCTAssertFalse(firstStore.showsAtLaunch)
    XCTAssertTrue(secondStore.showsAtLaunch)
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
