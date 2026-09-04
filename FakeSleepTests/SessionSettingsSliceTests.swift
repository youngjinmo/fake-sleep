import Foundation
import XCTest
@testable import FakeSleep

final class SessionSettingsStoreTests: XCTestCase {
  func test세션시간프리셋은정해진다섯가지순서로제공된다() {
    // Given: 제품에서 허용한 세션 시간 목록이 있다.
    // When: duration preset을 읽는다.
    let presets = SessionDuration.presets

    // Then: 30분, 1시간, 2시간, 4시간, 무제한만 제공한다.
    XCTAssertEqual(presets, [.minutes(30), .minutes(60), .minutes(120), .minutes(240), .indefinite])
  }

  func test신규저장소는확정된기본값을제공한다() {
    // Given: 비어 있는 독립 UserDefaults suite가 주입되어 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)

    // When: 세션 기본 설정을 읽는다.
    let settings = store.settings

    // Then: 안전 모드, 무제한, 배터리 10%와 미표시 상태가 기본값이다.
    XCTAssertEqual(settings.defaultMode, .secureLeave)
    XCTAssertEqual(settings.defaultDuration, .indefinite)
    XCTAssertEqual(settings.batteryCutoffPercent, 10)
    XCTAssertFalse(store.isOnboardingCompleted)
  }

  func test유효한설정은각키에저장되고새저장소에서복원된다() {
    // Given: 독립 UserDefaults suite에 연결된 저장소가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)
    let settings = SessionSettings(
      defaultMode: .blackout,
      defaultDuration: .minutes(120),
      batteryCutoffPercent: 0
    )

    // When: 설정과 온보딩 완료 상태를 저장한다.
    store.save(settings)
    store.markOnboardingCompleted(version: 1)
    let restored = SessionSettingsStore(defaults: defaults)

    // Then: 설정과 버전이 모두 그대로 복원된다.
    XCTAssertEqual(restored.settings, settings)
    XCTAssertTrue(restored.isOnboardingCompleted)
    XCTAssertEqual(defaults.integer(forKey: "onboarding.version"), 1)
  }

  func test허용되지않은저장값은필드별기본값으로복구된다() {
    // Given: mode, duration, battery 값이 저장 형식 및 범위를 벗어나 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    defaults.set("not-a-mode", forKey: "session.defaultMode")
    defaults.set(["unexpected": true], forKey: "session.defaultDuration")
    defaults.set(101, forKey: "session.batteryCutoffPercent")
    let store = SessionSettingsStore(defaults: defaults)

    // When: 저장된 기본 설정을 읽는다.
    let settings = store.settings

    // Then: 유효하지 않은 필드만 각 기본값으로 대체된다.
    XCTAssertEqual(settings.defaultMode, .secureLeave)
    XCTAssertEqual(settings.defaultDuration, .indefinite)
    XCTAssertEqual(settings.batteryCutoffPercent, 10)
  }

  func test배터리기준은0과100을포함한범위만허용한다() {
    // Given: 독립 저장소가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)

    // When: 경계값과 범위를 벗어난 값을 각각 저장한다.
    store.setBatteryCutoffPercent(0)
    XCTAssertEqual(store.settings.batteryCutoffPercent, 0)
    store.setBatteryCutoffPercent(100)
    XCTAssertEqual(store.settings.batteryCutoffPercent, 100)
    store.setBatteryCutoffPercent(-1)
    XCTAssertEqual(store.settings.batteryCutoffPercent, 10)
    store.setBatteryCutoffPercent(101)
    XCTAssertEqual(store.settings.batteryCutoffPercent, 10)
  }

  func test온보딩을취소하면부분설정과완료버전이저장되지않는다() {
    // Given: 완료되지 않은 신규 저장소와 편집 중 설정이 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)
    let original = store.settings

    // When: 편집 값을 버리고 온보딩을 취소한다.
    store.cancelOnboarding()

    // Then: 기본 설정과 완료 버전이 변경되지 않는다.
    XCTAssertEqual(store.settings, original)
    XCTAssertFalse(store.isOnboardingCompleted)
    XCTAssertNil(defaults.object(forKey: "onboarding.version"))
  }

  func testblackout안전소개표시는저장소간유지되고초기값은미표시다() {
    // Given: 비어 있는 독립 UserDefaults suite가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)

    // When: blackout 안전 소개를 표시 완료로 저장하고 새 저장소를 만든다.
    XCTAssertFalse(store.isBlackoutSafetyIntroShown)
    store.setBlackoutSafetyIntroShown(true)
    let restored = SessionSettingsStore(defaults: defaults)

    // Then: 소개 표시 여부가 저장소 간 유지된다.
    XCTAssertTrue(restored.isBlackoutSafetyIntroShown)
  }
}
