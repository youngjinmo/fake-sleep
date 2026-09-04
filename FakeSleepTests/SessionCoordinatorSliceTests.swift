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

  private func makeCoordinator(
    sleep: SessionSleepPreventerSpy = SessionSleepPreventerSpy(),
    power: SessionPowerMonitorSpy = SessionPowerMonitorSpy(snapshot: PowerSnapshot(isUsingBattery: false, batteryPercent: nil)),
    scheduler: SessionSchedulerSpy = SessionSchedulerSpy(),
    overlay: SessionOverlayPresenterSpy = SessionOverlayPresenterSpy(),
    screens: [ScreenDescriptor] = [ScreenDescriptor(id: 1, frame: .zero)]
  ) -> FakeSleepCoordinator {
    FakeSleepCoordinator(
      screenProvider: SessionScreenProviderSpy(screens: screens),
      overlayPresenter: overlay,
      hotKeyRegistrar: SessionHotKeyRegistrarSpy(),
      cursor: SessionCursorSpy(),
      sleepPreventer: sleep,
      powerMonitor: power,
      scheduler: scheduler
    )
  }
}
