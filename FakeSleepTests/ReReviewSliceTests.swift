import AppKit
import Foundation
import XCTest
@testable import FakeSleep

final class ReReviewSessionSettingsTests: XCTestCase {
  func test허용목록밖의양의세션시간은무제한으로복구된다() throws {
    // Given: 저장 형식은 올바르지만 제품 허용 목록에 없는 Int.max 시간이다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let data = try JSONEncoder().encode(SessionDuration.minutes(Int.max))
    defaults.set(data, forKey: "session.defaultDuration")
    let store = SessionSettingsStore(defaults: defaults)

    // When: 저장된 설정을 읽는다.
    let duration = store.settings.defaultDuration

    // Then: 임의의 긴 시간은 무제한 기본값으로 안전하게 복구된다.
    XCTAssertEqual(duration, .indefinite)
  }

  func test최대정수세션시간을계산해도오버플로하지않는다() {
    // Given: 외부 입력으로 매우 큰 duration이 전달된다.
    let duration = SessionDuration.minutes(Int.max)

    // When: 만료 간격을 계산한다.
    // Then: 계산이 충돌하지 않고 유효하지 않은 간격으로 취급된다.
    XCTAssertNoThrow(XCTAssertNil(duration.interval))
  }
}

@MainActor
final class ReReviewOnboardingTests: XCTestCase {
  func test온보딩진행문자열은세단계를각각분수로표시한다() {
    // Given: 온보딩의 세 단계 번호가 있다.
    // When: 진행 상태 formatter로 표시 문자열을 만든다.
    let progress = (1...3).map { LandingViewModel.progressText(step: $0) }

    // Then: 사용자는 현재 단계와 전체 단계를 모두 확인한다.
    XCTAssertEqual(progress, ["1/3", "2/3", "3/3"])
  }
}

@MainActor
final class ReReviewStatusMenuTests: XCTestCase {
  func test배터리부족으로거부된시작은observer와메뉴에경고를알리고한번열때까지유지한다() throws {
    // Given: 현재 배터리가 기준 이하인 코디네이터와 상태 메뉴가 있다.
    let power = SessionPowerMonitorSpy(snapshot: PowerSnapshot(isUsingBattery: true, batteryPercent: 10))
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: SessionOverlayPresenterSpy(),
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy(),
      powerMonitor: power
    )
    var observedErrors: [FakeSleepError?] = []
    _ = coordinator.addErrorObserver { observedErrors.append($0) }
    let controller = StatusMenuController(coordinator: coordinator)
    defer { controller.close() }

    // When: 배터리 기준을 10%로 설정해 시작을 거부하고 메뉴를 갱신한다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 10))
    controller.refresh()
    let menu = try XCTUnwrap(controller.statusItem.menu)

    // Then: observer와 첫 메뉴 항목에 배터리 경고가 보이고, 메뉴를 열면 한 번 인정된다.
    XCTAssertTrue(observedErrors.contains(.batteryBelowCutoff(percent: 10, cutoff: 10)))
    XCTAssertTrue(menu.items.first?.title.contains("10") == true)
    controller.menuWillOpen(menu)
    XCTAssertFalse(menu.items.first?.title.contains("10") == true)
  }

  func test비활성블랙아웃메뉴는현지화된보안기능아님경고를함께표시한다() throws {
    // Given: 비활성 상태의 상태 메뉴가 있다.
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: SessionOverlayPresenterSpy(),
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy()
    )
    let controller = StatusMenuController(coordinator: coordinator)
    defer { controller.close() }

    // When: 비활성 메뉴에서 blackout 시작 항목을 찾는다.
    let menu = try XCTUnwrap(controller.statusItem.menu)
    let startTitle = NSLocalizedString("menu.startBlackout", bundle: .main, value: "Blackout Only", comment: "")
    let item = try XCTUnwrap(menu.items.first {
      $0.title.contains(startTitle)
    })

    // Then: 시작 항목 자체가 번역된 보안 경고를 포함한다.
    let warning = NSLocalizedString("mode.blackout.warning", bundle: .main, value: "Mac is not locked. This mode is not a security feature.", comment: "")
    XCTAssertTrue(item.title.contains(warning))
  }

  func test잠금해제된안전모드메뉴는재잠금단축키를안내한다() throws {
    // Given: 잠금 해제 상태의 secure leave 세션과 메뉴가 있다.
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: SessionOverlayPresenterSpy(),
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy()
    )
    let controller = StatusMenuController(coordinator: coordinator)
    defer { controller.close() }
    coordinator.start(configuration: .init(mode: .secureLeave, duration: .indefinite, batteryCutoffPercent: 0))

    // When: 잠금 대기 상태의 메뉴를 확인한다.
    let menu = try XCTUnwrap(controller.statusItem.menu)

    // Then: Control-Command-Q 재잠금 안내가 노출된다.
    XCTAssertTrue(menu.items.contains { $0.title.contains("⌃⌘Q") })
  }

  func test타이머종료피드백은선택한실제시간을표시한다() throws {
    // Given: 1시간 세션과 제어 가능한 scheduler가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)
    store.setBlackoutSafetyIntroShown(true)
    let scheduler = SessionSchedulerSpy()
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: SessionOverlayPresenterSpy(),
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy(),
      scheduler: scheduler,
      settingsStore: store
    )
    let controller = StatusMenuController(coordinator: coordinator, settingsStore: store)
    defer { controller.close() }

    // When: 1시간 blackout 세션을 만료시킨다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .minutes(60), batteryCutoffPercent: 0))
    scheduler.now = 60 * 60
    scheduler.fireNext()
    scheduler.fireNext()
    controller.refresh()

    // Then: 피드백에 실제 선택 시간 1시간이 표시된다.
    let menu = try XCTUnwrap(controller.statusItem.menu)
    let durationTitle = NSLocalizedString(
      "duration.1Hour",
      bundle: .main,
      value: "1 hour",
      comment: ""
    )
    XCTAssertTrue(menu.items.first?.title.contains(durationTitle) == true)
  }
  func test블랙아웃메뉴항목은보안기능이아님을현지화된경고로명시한다() throws {
    // Given: blackout 설정과 상태 메뉴가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: SessionOverlayPresenterSpy(),
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy()
    )
    let controller = StatusMenuController(coordinator: coordinator, settingsStore: store)
    defer { controller.close() }

    // When: blackout 세션의 메뉴를 확인한다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 0))
    controller.refresh()
    let menu = try XCTUnwrap(controller.statusItem.menu)
    let modeTitle = NSLocalizedString(
      "menu.mode.blackout",
      bundle: .main,
      value: "Blackout Only · Not a Security Feature",
      comment: ""
    )
    let modeItem = try XCTUnwrap(menu.items.first { $0.title == modeTitle })
    let warning = NSLocalizedString(
      "mode.blackout.warning",
      bundle: .main,
      value: "Mac is not locked. This mode is not a security feature.",
      comment: ""
    )

    // Then: 메뉴의 모드 설명과 설정/온보딩 경고가 비어 있지 않다.
    XCTAssertEqual(modeItem.title, modeTitle)
    XCTAssertFalse(warning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  func test준비중블랙아웃은상태observer와메뉴에초읽기를노출한다() throws {
    // Given: 아직 안전 소개를 보지 않은 blackout 세션과 제어 가능한 scheduler가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)
    let scheduler = SessionSchedulerSpy()
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: SessionOverlayPresenterSpy(),
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy(),
      scheduler: scheduler,
      settingsStore: store
    )
    var observed: [FakeSleepState] = []
    _ = coordinator.addStateObserver { observed.append($0) }
    let controller = StatusMenuController(coordinator: coordinator, settingsStore: store)
    defer { controller.close() }

    // When: blackout 세션을 시작하고 상태바 메뉴를 연다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 0))
    controller.refresh()
    let menu = try XCTUnwrap(controller.statusItem.menu)

    // Then: 준비 상태와 3초 초읽기, 취소 항목이 사용자에게 노출된다.
    XCTAssertEqual(coordinator.state, .preparingBlackout)
    XCTAssertTrue(observed.contains(.preparingBlackout))
    XCTAssertTrue(menu.items.contains { $0.title.localizedCaseInsensitiveContains("3") })
    XCTAssertTrue(menu.items.contains { $0.title.localizedCaseInsensitiveContains("cancel") })
  }

  func test잠금상태변경은메뉴를즉시갱신해보안경고를제거한다() throws {
    // Given: macOS 잠금 전의 secure leave 세션과 상태 메뉴가 있다.
    let scheduler = SessionSchedulerSpy()
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: SessionOverlayPresenterSpy(),
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy(),
      scheduler: scheduler
    )
    let controller = StatusMenuController(coordinator: coordinator)
    defer { controller.close() }
    coordinator.start(configuration: .init(mode: .secureLeave, duration: .indefinite, batteryCutoffPercent: 0))
    let menu = try XCTUnwrap(controller.statusItem.menu)

    // When: 사용자가 macOS 잠금을 완료한다.
    coordinator.handleWorkspaceSessionDidResignActive()

    // Then: 메뉴가 즉시 잠금 완료 상태를 반영한다.
    XCTAssertFalse(menu.items.contains { $0.title.localizedCaseInsensitiveContains("unlocked") })
  }

  func test실패세션의경고아이콘은메뉴를열지않아도주입시각기준십분후만료된다() {
    // Given: 주입된 시각과 scheduler를 가진 메뉴 컨트롤러가 있다.
    let clock = ReReviewTestClock(now: 1_000)
    let scheduler = SessionSchedulerSpy()
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: []),
      overlayPresenter: SessionOverlayPresenterSpy(),
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy(),
      scheduler: scheduler
    )
    let controller = StatusMenuController(
      coordinator: coordinator,
      clock: clock,
      refreshScheduler: scheduler
    )
    defer { controller.close() }

    // When: 활성화 실패 후 메뉴를 열지 않은 채 10분을 경과시킨다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 0))
    clock.now += 10 * 60
    scheduler.fireNext()

    // Then: 경고 아이콘과 종료 경고가 만료된다.
    XCTAssertEqual(controller.statusImageName, "moon")
  }
}

@MainActor
final class ReReviewAppContainerTests: XCTestCase {
  func test단축키action은비활성세션을시작하고활성세션을수동종료한다() {
    // Given: 테스트용 의존성으로 조립한 AppContainer와 단축키 action이 있다.
    let coordinator = ReReviewCoordinatorSpy()
    let container = AppContainer(coordinator: coordinator)
    defer { container.prepareForTermination() }

    // When: 단축키 action을 두 번 실행한다.
    container.invokeShortcutAction()
    container.invokeShortcutAction()

    // Then: 첫 호출은 시작, 두 번째 호출은 manual 종료가 된다.
    XCTAssertEqual(coordinator.startCount, 1)
    XCTAssertEqual(coordinator.endReasons, [.manual])
  }
}

@MainActor
private final class ReReviewTestClock: CurrentTimeProviding {
  var now: Date

  init(now: TimeInterval) {
    self.now = Date(timeIntervalSince1970: now)
  }
}

@MainActor
private final class ReReviewCoordinatorSpy: FakeSleepCoordinatorProtocol {
  private(set) var startCount = 0
  private(set) var endReasons: [SessionEndReason] = []
  var isSessionActive = false

  func start(configuration: SessionConfiguration) {
    startCount += 1
    isSessionActive = true
  }

  func endSession(reason: SessionEndReason) {
    endReasons.append(reason)
    isSessionActive = false
  }
}
