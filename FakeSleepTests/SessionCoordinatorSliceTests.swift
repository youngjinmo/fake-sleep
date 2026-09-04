import Foundation
import XCTest
@testable import FakeSleep

@MainActor
final class SessionCoordinatorTests: XCTestCase {
  func test안전모드세션은sleep방지후잠금대기상태로시작한다() {
    // Given: 배터리 여유가 있고 모든 시스템 서비스가 정상이다.
    let sleep = SessionSleepPreventerSpy()
    let power = SessionPowerMonitorSpy(snapshot: PowerSnapshot(isUsingBattery: true, batteryPercent: 80))
    let scheduler = SessionSchedulerSpy()
    let coordinator = makeCoordinator(sleep: sleep, power: power, scheduler: scheduler)
    let configuration = SessionConfiguration(mode: .secureLeave, duration: .indefinite, batteryCutoffPercent: 10)

    // When: 안전하게 자리 비우기 세션을 시작한다.
    coordinator.start(configuration: configuration)

    // Then: activity가 먼저 시작되고 실제 잠금 전에는 awaitingSystemLock이다.
    XCTAssertEqual(sleep.events, [.begin])
    XCTAssertEqual(coordinator.state, .awaitingSystemLock)
    XCTAssertNil(coordinator.lastEndReason)
    XCTAssertEqual(coordinator.currentSession?.lockState, .unlocked)
  }

  func test잠금해제알림은세션을끝내지않고active로전환한다() {
    // Given: 안전 모드가 macOS 잠금을 기다리고 있다.
    let coordinator = makeCoordinator()
    coordinator.start(configuration: .init(mode: .secureLeave, duration: .indefinite, batteryCutoffPercent: 10))

    // When: 세션 resign 알림을 처리한다.
    coordinator.handleWorkspaceSessionDidResignActive()

    // Then: 안내 패널을 닫고 active 세션으로 전환한다.
    XCTAssertEqual(coordinator.state, .active)
    XCTAssertEqual(coordinator.currentSession?.lockState, .locked)
    XCTAssertNil(coordinator.lastEndReason)
  }

  func test활성화된안전세션에서사용자가다시활동하면잠금상태만unlocked로변경된다() {
    // Given: 잠금 알림을 받아 active가 된 안전 모드 세션이 있다.
    let coordinator = makeCoordinator()
    coordinator.start(configuration: .init(mode: .secureLeave, duration: .indefinite, batteryCutoffPercent: 10))
    coordinator.handleWorkspaceSessionDidResignActive()

    // When: 사용자가 macOS에서 다시 활동하여 세션이 become active가 된다.
    coordinator.handleWorkspaceSessionDidBecomeActive()

    // Then: 세션은 종료되지 않고 잠금 상태만 unlocked로 갱신된다.
    XCTAssertEqual(coordinator.state, .active)
    XCTAssertEqual(coordinator.currentSession?.lockState, .unlocked)
    XCTAssertNil(coordinator.lastEndReason)
  }

  func test제한된안전세션은잠금대기후에도원래만료시각을유지하고timerExpired로종료된다() {
    // Given: 30분 제한 안전 모드 세션이 잠금 대기 중이다.
    let scheduler = SessionSchedulerSpy()
    let coordinator = makeCoordinator(scheduler: scheduler)
    coordinator.start(configuration: .init(mode: .secureLeave, duration: .minutes(30), batteryCutoffPercent: 0))
    XCTAssertEqual(scheduler.scheduledIntervals, [60, 30 * 60])
    XCTAssertEqual(coordinator.remainingDuration, 30 * 60, accuracy: 1)

    // When: 잠금되고 30분 시점에 세션 만료 callback을 실행한다.
    coordinator.handleWorkspaceSessionDidResignActive()
    scheduler.now = 30 * 60
    scheduler.fire(at: 1)

    // Then: 잠금 대기 만료가 아니라 세션 제한 시간 만료로 종료된다.
    XCTAssertEqual(coordinator.state, .inactive)
    XCTAssertEqual(coordinator.lastEndReason, .timerExpired)
  }

  func test첫안전세션잠금대기에는노출가능한countdown이있고취소하면사라진다() {
    // Given: 안전 모드가 시스템 잠금을 기다리는 중이다.
    let scheduler = SessionSchedulerSpy()
    let coordinator = makeCoordinator(scheduler: scheduler)
    coordinator.start(configuration: .init(mode: .secureLeave, duration: .indefinite, batteryCutoffPercent: 0))

    // When: 시간이 흐른 뒤 사용자가 세션을 취소한다.
    scheduler.now = 15
    XCTAssertEqual(coordinator.lockCountdownRemaining, 45, accuracy: 0.1)
    coordinator.endSession(reason: .manual)

    // Then: 세션이 종료되고 countdown도 0으로 내려간다.
    XCTAssertEqual(coordinator.state, .inactive)
    XCTAssertEqual(coordinator.lockCountdownRemaining, 0)
  }

  func test잠금대기timeout은공통종료경로로모든서비스를정리한다() {
    // Given: 잠금 대기 timer가 등록된 안전 모드 세션이 있다.
    let sleep = SessionSleepPreventerSpy()
    let power = SessionPowerMonitorSpy(snapshot: PowerSnapshot(isUsingBattery: true, batteryPercent: 80))
    let scheduler = SessionSchedulerSpy()
    let coordinator = makeCoordinator(sleep: sleep, power: power, scheduler: scheduler)
    coordinator.start(configuration: .init(mode: .secureLeave, duration: .indefinite, batteryCutoffPercent: 10))

    // When: 잠금 대기 만료 callback을 실행한다.
    scheduler.fireNext()

    // Then: lockTimedOut으로 inactive이 되고 timer, monitor, activity가 종료된다.
    XCTAssertEqual(coordinator.state, .inactive)
    XCTAssertEqual(coordinator.lastEndReason, .lockTimedOut)
    XCTAssertEqual(sleep.events, [.begin, .end])
    XCTAssertEqual(power.stopCount, 1)
    XCTAssertEqual(scheduler.cancelCount, 1)
  }

  func test화면가리기overlay실패는activity와생성된창을롤백한다() {
    // Given: 두 화면 중 하나만 덮을 수 있다.
    let overlay = SessionOverlayPresenterSpy(coveredScreenIDs: [1])
    let sleep = SessionSleepPreventerSpy()
    let coordinator = makeCoordinator(
      sleep: sleep,
      overlay: overlay,
      screens: [ScreenDescriptor(id: 1, frame: .zero), ScreenDescriptor(id: 2, frame: .zero)]
    )

    // When: 화면만 가리기 세션을 시작한다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .minutes(30), batteryCutoffPercent: 10))

    // Then: active로 전환하지 않고 activationFailed와 함께 모두 복구한다.
    guard case .activationFailed = coordinator.lastEndReason else {
      return XCTFail("활성화 실패 사유가 기록되어야 합니다")
    }
    XCTAssertEqual(coordinator.state, .inactive)
    XCTAssertEqual(overlay.removeAllCount, 1)
    XCTAssertEqual(sleep.events, [.begin, .end])
  }

  func test기본복원경로가있고Escape등록만실패해도blackout은시작되고경고를노출한다() {
    // Given: 기본 단축키 복원 경로는 살아 있지만 긴급 Escape 등록만 실패한다.
    let hotKey = SessionHotKeyRegistrarSpy()
    hotKey.emergencyRegistrationSucceeds = false
    let coordinator = makeCoordinator(hotKeyRegistrar: hotKey)

    // When: 화면만 가리기 세션을 시작한다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 0))

    // Then: 복원 가능한 blackout은 활성화하고 긴급 복원 불가 경고를 유지한다.
    XCTAssertEqual(coordinator.state, .active)
    XCTAssertEqual(coordinator.error, .emergencyEscapeUnavailable)
    XCTAssertNil(coordinator.lastEndReason)
  }

  func test활성세션중AC에서배터리로전환되어기준이하면즉시lowBattery로종료한다() {
    // Given: 배터리 기준을 적용한 blackout 세션이 AC에서 실행 중이다.
    let power = SessionPowerMonitorSpy(snapshot: PowerSnapshot(isUsingBattery: false, batteryPercent: nil))
    let coordinator = makeCoordinator(power: power)
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 20))

    // When: AC가 분리되고 배터리 잔량이 기준 이하라는 알림을 받는다.
    power.emit(PowerSnapshot(isUsingBattery: true, batteryPercent: 20))

    // Then: 알림 callback에서 즉시 lowBattery 사유로 세션이 종료된다.
    XCTAssertEqual(coordinator.state, .inactive)
    XCTAssertEqual(coordinator.lastEndReason, .lowBattery(percent: 20))
  }

  func test배터리기준이하에서시작하면세션을거부하고activity를시작하지않는다() {
    // Given: 배터리 10%이고 종료 기준도 10%이다.
    let sleep = SessionSleepPreventerSpy()
    let power = SessionPowerMonitorSpy(snapshot: PowerSnapshot(isUsingBattery: true, batteryPercent: 10))
    let coordinator = makeCoordinator(sleep: sleep, power: power)

    // When: 세션 시작을 요청한다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 10))

    // Then: lowBattery 사유로 거부하고 sleep 방지는 시작하지 않는다.
    XCTAssertEqual(coordinator.state, .inactive)
    XCTAssertEqual(coordinator.lastEndReason, .lowBattery(percent: 10))
    XCTAssertTrue(sleep.events.isEmpty)
  }

  func testtimer만료와수동종료는동일한정리경로를사용한다() {
    // Given: 제한 세션이 scheduler에 등록되어 있다.
    let sleep = SessionSleepPreventerSpy()
    let scheduler = SessionSchedulerSpy()
    let coordinator = makeCoordinator(sleep: sleep, scheduler: scheduler)
    coordinator.start(configuration: .init(mode: .blackout, duration: .minutes(30), batteryCutoffPercent: 0))
    XCTAssertEqual(coordinator.remainingDuration, 30 * 60, accuracy: 1)

    // When: 사용자가 수동 종료한다.
    coordinator.endSession(reason: .manual)

    // Then: inactive이 되고 모든 종료 호출이 정확히 한 번 실행된다.
    XCTAssertEqual(coordinator.state, .inactive)
    XCTAssertEqual(coordinator.lastEndReason, .manual)
    XCTAssertEqual(sleep.events, [.begin, .end])
    XCTAssertEqual(scheduler.cancelCount, 1)

    // When: 종료를 반복한다.
    coordinator.endSession(reason: .manual)

    // Then: 정리 호출이 누적되지 않는다.
    XCTAssertEqual(sleep.events, [.begin, .end])
    XCTAssertEqual(scheduler.cancelCount, 1)
  }

  func test블랙아웃첫사용은3초준비중취소하면오버레이와활동을정리한다() {
    // Given: blackout 안전 소개를 아직 표시하지 않은 저장소와 제어 가능한 scheduler가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)
    let scheduler = SessionSchedulerSpy()
    let sleep = SessionSleepPreventerSpy()
    let overlay = SessionOverlayPresenterSpy()
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: overlay,
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy(),
      sleepPreventer: sleep,
      powerMonitor: SessionPowerMonitorSpy(snapshot: PowerSnapshot(isUsingBattery: false, batteryPercent: nil)),
      scheduler: scheduler,
      settingsStore: store
    )

    // When: blackout 세션을 시작하고 준비 중 취소한다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 0))
    XCTAssertEqual(coordinator.state, .preparingBlackout)
    XCTAssertEqual(coordinator.blackoutPreparationRemaining, 3, accuracy: 0.1)
    XCTAssertEqual(scheduler.scheduledIntervals, [3])
    coordinator.cancelBlackoutPreparation()

    // Then: 표시나 활동이 남지 않고 소개 완료 플래그도 기록하지 않는다.
    XCTAssertEqual(coordinator.state, .inactive)
    XCTAssertEqual(sleep.events, [.begin, .end])
    XCTAssertEqual(overlay.removeAllCount, 1)
    XCTAssertTrue(overlay.coveredScreenIDs.isEmpty)
    XCTAssertFalse(store.isBlackoutSafetyIntroShown)
  }

  func test블랙아웃첫사용은3초후오버레이를표시하고안전소개를완료한다() {
    // Given: blackout 안전 소개를 아직 표시하지 않은 저장소가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)
    let scheduler = SessionSchedulerSpy()
    let overlay = SessionOverlayPresenterSpy()
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: overlay,
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy(),
      scheduler: scheduler,
      settingsStore: store
    )

    // When: blackout 세션을 시작하고 3초 countdown을 완료한다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 0))
    scheduler.fireNext()

    // Then: 오버레이가 활성화되고 소개 완료 플래그와 2초 복원 안내가 기록된다.
    XCTAssertEqual(coordinator.state, .active)
    XCTAssertEqual(overlay.coveredScreenIDs, [1])
    XCTAssertTrue(store.isBlackoutSafetyIntroShown)
    XCTAssertEqual(overlay.restoreHintEvents.map(\.visible), [true])
    XCTAssertEqual(scheduler.scheduledIntervals, [3, 2])
  }

  func test블랙아웃안전소개를완료한이후사용은카운트다운없이즉시활성화된다() {
    // Given: blackout 안전 소개를 이미 완료한 저장소가 있다.
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

    // When: blackout 세션을 시작한다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 0))

    // Then: 준비 상태를 거치지 않고 즉시 활성화된다.
    XCTAssertEqual(coordinator.state, .active)
    XCTAssertEqual(coordinator.blackoutPreparationRemaining, 0)
    XCTAssertTrue(scheduler.scheduledIntervals.isEmpty)
  }

  func test복원안내는2초후사라지고동작감소설정이면서서히사라지지않는다() {
    // Given: 이미 안전 소개를 완료했고 Reduce Motion이 활성화된 blackout coordinator가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)
    store.setBlackoutSafetyIntroShown(true)
    let scheduler = SessionSchedulerSpy()
    let overlay = SessionOverlayPresenterSpy()
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: overlay,
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy(),
      scheduler: scheduler,
      settingsStore: store,
      reduceMotion: true
    )

    // When: 세션을 활성화하고 2초 복원 안내 제거 callback을 실행한다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 0))
    scheduler.fireNext()

    // Then: 안내 제거가 animated=false로 전달된다.
    XCTAssertEqual(overlay.restoreHintEvents.map(\.visible), [true, false])
    XCTAssertEqual(overlay.restoreHintEvents.map(\.animated), [false, false])
  }

  func test블랙아웃을다시시작해도복원안내를매번표시한다() {
    // Given: 첫 사용 안내를 이미 완료한 저장소와 오버레이가 있다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SessionSettingsStore(defaults: defaults)
    store.setBlackoutSafetyIntroShown(true)
    let scheduler = SessionSchedulerSpy()
    let overlay = SessionOverlayPresenterSpy()
    let coordinator = FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: [ScreenDescriptor(id: 1, frame: .zero)]),
      overlayPresenter: overlay,
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy(),
      scheduler: scheduler,
      settingsStore: store
    )

    // When: blackout 세션을 두 번 시작한다.
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 0))
    coordinator.endSession(reason: .manual)
    coordinator.start(configuration: .init(mode: .blackout, duration: .indefinite, batteryCutoffPercent: 0))

    // Then: 두 번째 세션도 복원 안내를 새로 표시한다.
    XCTAssertEqual(overlay.restoreHintEvents.map(\.visible), [true, true])
  }

  private func makeCoordinator(
    sleep: SessionSleepPreventerSpy = SessionSleepPreventerSpy(),
    power: SessionPowerMonitorSpy = SessionPowerMonitorSpy(snapshot: PowerSnapshot(isUsingBattery: false, batteryPercent: nil)),
    scheduler: SessionSchedulerSpy = SessionSchedulerSpy(),
    overlay: SessionOverlayPresenterSpy = SessionOverlayPresenterSpy(),
    screens: [ScreenDescriptor] = [ScreenDescriptor(id: 1, frame: .zero)],
    hotKeyRegistrar: SessionHotKeyRegistrarSpy = SessionHotKeyRegistrarSpy()
  ) -> FakeSleepCoordinator {
    FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: screens),
      overlayPresenter: overlay,
      hotKeyRegistrar: hotKeyRegistrar,
      cursor: SessionCursorSpy(),
      sleepPreventer: sleep,
      powerMonitor: power,
      scheduler: scheduler
    )
  }
}
