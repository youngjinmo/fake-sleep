import AppKit
import XCTest
@testable import FakeSleep

@MainActor
final class FakeSleepTests: XCTestCase {
  func testAppContainerCanBeCreated() {
    XCTAssertNotNil(AppContainer())
  }

  func testAwake에서활성화하면모든화면을덮고커서를숨긴다() {
    let screenProvider = ScreenProviderSpy(screens: [.init(id: 1), .init(id: 2)])
    let overlayPresenter = OverlayPresenterSpy()
    let hotKeyRegistrar = HotKeyRegistrarSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter, hotKeyRegistrar: hotKeyRegistrar, cursor: cursor)

    // Given: 코디네이터가 깨어 있고 복구 경로를 등록할 수 있다.
    XCTAssertEqual(coordinator.state, .awake)

    // When: 가짜 슬립을 시작한다.
    coordinator.activate()

    // Then: 모든 화면이 덮이고 커서는 한 번만 숨겨진다.
    XCTAssertEqual(coordinator.state, .fakeSleeping)
    XCTAssertEqual(overlayPresenter.lastReconciledScreenIDs, [1, 2])
    XCTAssertEqual(cursor.hideCount, 1)
    XCTAssertEqual(cursor.unhideCount, 0)
  }

  func test활성상태에서복원하면오버레이와커서를복원한다() {
    let overlayPresenter = OverlayPresenterSpy()
    let hotKeyRegistrar = HotKeyRegistrarSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(overlayPresenter: overlayPresenter, hotKeyRegistrar: hotKeyRegistrar, cursor: cursor)

    // Given: 가짜 슬립이 활성 상태다.
    coordinator.activate()

    // When: 화면을 복원한다.
    coordinator.restore()

    // Then: 오버레이, 커서, Escape 등록을 되돌린다.
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertEqual(overlayPresenter.removeAllCount, 1)
    XCTAssertEqual(cursor.unhideCount, 1)
    XCTAssertEqual(hotKeyRegistrar.unregisterEmergencyEscapeCount, 1)
  }

  func test복원을반복해도커서와정리호출이중복되지않는다() {
    let overlayPresenter = OverlayPresenterSpy()
    let hotKeyRegistrar = HotKeyRegistrarSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(overlayPresenter: overlayPresenter, hotKeyRegistrar: hotKeyRegistrar, cursor: cursor)

    // Given: 활성화 후 한 번 복원했다.
    coordinator.activate()
    coordinator.restore()

    // When: 이미 깨어 있는 상태에서 복원을 반복한다.
    coordinator.restore()

    // Then: 실제 자원 정리는 최초 복원에만 일어난다.
    XCTAssertEqual(overlayPresenter.removeAllCount, 1)
    XCTAssertEqual(cursor.unhideCount, 1)
    XCTAssertEqual(hotKeyRegistrar.unregisterEmergencyEscapeCount, 1)
  }

  func test빠르게두번토글하면활성화와복원이각각한번만수행된다() {
    let overlayPresenter = OverlayPresenterSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(overlayPresenter: overlayPresenter, cursor: cursor)

    // Given: 깨어 있는 상태다.
    XCTAssertEqual(coordinator.state, .awake)

    // When: 토글을 연속으로 두 번 호출한다.
    coordinator.toggle()
    coordinator.toggle()

    // Then: 중복 hide 없이 최종 상태가 깨어 있음이다.
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertEqual(overlayPresenter.reconcileCount, 1)
    XCTAssertEqual(cursor.hideCount, 1)
    XCTAssertEqual(cursor.unhideCount, 1)
  }

  func test화면이없으면활성화하지않고오류와정리를남긴다() {
    let screenProvider = ScreenProviderSpy(screens: [])
    let overlayPresenter = OverlayPresenterSpy()
    let hotKeyRegistrar = HotKeyRegistrarSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter, hotKeyRegistrar: hotKeyRegistrar, cursor: cursor)

    // Given: 연결된 화면이 없다.
    // When: 활성화를 시도한다.
    coordinator.activate()

    // Then: 활성화하지 않고 Escape와 자원을 정리한다.
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertNotNil(coordinator.error)
    XCTAssertEqual(overlayPresenter.reconcileCount, 0)
    XCTAssertEqual(overlayPresenter.removeAllCount, 1)
    XCTAssertEqual(cursor.hideCount, 0)
    XCTAssertEqual(hotKeyRegistrar.unregisterEmergencyEscapeCount, 1)
  }

  func test화면이없어활성화에실패한뒤복원하면오류를지운다() {
    let screenProvider = ScreenProviderSpy(screens: [])
    let coordinator = makeCoordinator(screenProvider: screenProvider)

    // Given: 화면이 없어 활성화에 실패하고 오류가 남아 있다.
    coordinator.activate()
    XCTAssertNotNil(coordinator.error)

    // When: 깨어 있는 상태에서 복원한다.
    coordinator.restore()

    // Then: 오류가 지워진다.
    XCTAssertNil(coordinator.error)
  }

  func test일부화면만덮이면활성화를롤백한다() {
    let screenProvider = ScreenProviderSpy(screens: [.init(id: 1), .init(id: 2)])
    let overlayPresenter = OverlayPresenterSpy(coveredScreenIDs: [1])
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter, cursor: cursor)

    // Given: 오버레이 생성이 일부 화면에서 실패한다.
    // When: 활성화를 시도한다.
    coordinator.activate()

    // Then: 불완전한 활성화를 롤백하고 커서는 숨기지 않는다.
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertNotNil(coordinator.error)
    XCTAssertEqual(overlayPresenter.removeAllCount, 1)
    XCTAssertEqual(cursor.hideCount, 0)
  }

  func test기본복구경로가없어도Escape가성공하면활성화할수있다() {
    let hotKeyRegistrar = HotKeyRegistrarSpy(primaryRegistrationSucceeds: false)
    let overlayPresenter = OverlayPresenterSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(overlayPresenter: overlayPresenter, hotKeyRegistrar: hotKeyRegistrar, cursor: cursor)

    // Given: 기본 단축키 등록은 실패하지만 Escape 등록은 성공한다.
    // When: 활성화를 시도한다.
    coordinator.activate()

    // Then: Escape를 유일한 복구 경로로 활성화한다.
    XCTAssertEqual(coordinator.state, .fakeSleeping)
    XCTAssertEqual(overlayPresenter.reconcileCount, 1)
    XCTAssertEqual(cursor.hideCount, 1)
  }

  func test기본단축키와Escape가모두실패하면활성화하지않는다() {
    let hotKeyRegistrar = HotKeyRegistrarSpy(primaryRegistrationSucceeds: false, emergencyRegistrationSucceeds: false)
    let overlayPresenter = OverlayPresenterSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(overlayPresenter: overlayPresenter, hotKeyRegistrar: hotKeyRegistrar, cursor: cursor)

    // Given: 두 복구 경로를 모두 사용할 수 없다.
    // When: 활성화를 시도한다.
    coordinator.activate()

    // Then: 오버레이와 커서에 손대지 않고 실패한다.
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertNotNil(coordinator.error)
    XCTAssertEqual(overlayPresenter.reconcileCount, 0)
    XCTAssertEqual(cursor.hideCount, 0)
  }

  func test종료준비는활성상태를복원한다() {
    let overlayPresenter = OverlayPresenterSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(overlayPresenter: overlayPresenter, cursor: cursor)

    // Given: 가짜 슬립이 활성 상태다.
    coordinator.activate()

    // When: 종료를 준비한다.
    coordinator.prepareForTermination()

    // Then: 종료 전에 모든 자원을 복원한다.
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertEqual(overlayPresenter.removeAllCount, 1)
    XCTAssertEqual(cursor.unhideCount, 1)
  }

  func test활성상태에서화면이모두사라지면복원하고오류를남긴다() {
    let screenProvider = ScreenProviderSpy(screens: [.init(id: 1)])
    let overlayPresenter = OverlayPresenterSpy()
    let hotKeyRegistrar = HotKeyRegistrarSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter, hotKeyRegistrar: hotKeyRegistrar, cursor: cursor)

    // Given: 가짜 슬립이 활성 상태다.
    coordinator.activate()
    screenProvider.screens = []

    // When: 화면 구성 변경 콜백을 처리한다.
    coordinator.handleScreenConfigurationChange()

    // Then: 자원을 롤백하고 깨어 있는 상태와 오류를 알린다.
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertEqual(overlayPresenter.removeAllCount, 1)
    XCTAssertEqual(cursor.unhideCount, 1)
    XCTAssertEqual(hotKeyRegistrar.unregisterEmergencyEscapeCount, 1)
    XCTAssertNotNil(coordinator.error)
  }

  func test활성상태에서불완전한오버레이가감지되면복원하고오류를남긴다() {
    let screenProvider = ScreenProviderSpy(screens: [.init(id: 1), .init(id: 2)])
    let overlayPresenter = OverlayPresenterSpy()
    let hotKeyRegistrar = HotKeyRegistrarSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter, hotKeyRegistrar: hotKeyRegistrar, cursor: cursor)

    // Given: 활성화 후 오버레이가 일부 화면만 덮도록 바뀐다.
    coordinator.activate()
    overlayPresenter.partialMode = true
    overlayPresenter.coveredScreenIDs = [1]

    // When: 활성 상태의 화면 구성 콜백을 호출한다.
    coordinator.handleScreenConfigurationChange()

    // Then: 자원을 롤백하고 깨어 있는 상태와 오류를 알린다.
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertEqual(overlayPresenter.removeAllCount, 1)
    XCTAssertEqual(cursor.unhideCount, 1)
    XCTAssertEqual(hotKeyRegistrar.unregisterEmergencyEscapeCount, 1)
    XCTAssertNotNil(coordinator.error)
  }

  func testEscape핸들러를호출하면메인액터에서복원한다() async {
    let overlayPresenter = OverlayPresenterSpy()
    let hotKeyRegistrar = HotKeyRegistrarSpy()
    let cursor = CursorSpy()
    let coordinator = makeCoordinator(overlayPresenter: overlayPresenter, hotKeyRegistrar: hotKeyRegistrar, cursor: cursor)

    // Given: 가짜 슬립이 활성 상태이고 Escape 핸들러가 등록되어 있다.
    coordinator.activate()
    XCTAssertNotNil(hotKeyRegistrar.emergencyEscapeHandler)

    // When: 등록된 Escape 핸들러를 호출하고 메인 액터 작업이 실행될 때까지 기다린다.
    hotKeyRegistrar.emergencyEscapeHandler?()
    await Task.yield()

    // Then: 메인 액터에서 가짜 슬립을 복원한다.
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertEqual(overlayPresenter.removeAllCount, 1)
    XCTAssertEqual(cursor.unhideCount, 1)
  }

  func test상태와오류관찰콜백이변경값을받는다() {
    var observedStates: [FakeSleepState] = []
    var observedErrors: [FakeSleepError?] = []
    let screenProvider = ScreenProviderSpy(screens: [.init(id: 1)])
    let overlayPresenter = OverlayPresenterSpy()
    let hotKeyRegistrar = HotKeyRegistrarSpy()
    let cursor = CursorSpy()
    let coordinator = FakeSleepCoordinator(
      screenProvider: screenProvider,
      overlayPresenter: overlayPresenter,
      hotKeyRegistrar: hotKeyRegistrar,
      cursor: cursor,
      onStateChange: { observedStates.append($0) },
      onErrorChange: { observedErrors.append($0) }
    )

    // Given: 상태와 오류 변경을 관찰할 콜백을 등록한다.
    // When: 활성화한 뒤 화면을 모두 제거하고 활성 상태 콜백을 호출한다.
    coordinator.activate()
    screenProvider.screens = []
    coordinator.handleScreenConfigurationChange()

    // Then: 상태와 오류의 변경값이 각각 관찰된다.
    XCTAssertEqual(observedStates, [.fakeSleeping, .awake])
    XCTAssertEqual(observedErrors, [nil, .noScreens])
  }

  private func makeCoordinator(
    screenProvider: ScreenProviderSpy = ScreenProviderSpy(screens: [.init(id: 1)]),
    overlayPresenter: OverlayPresenterSpy = OverlayPresenterSpy(),
    hotKeyRegistrar: HotKeyRegistrarSpy = HotKeyRegistrarSpy(),
    cursor: CursorSpy = CursorSpy()
  ) -> FakeSleepCoordinator {
    FakeSleepCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter, hotKeyRegistrar: hotKeyRegistrar, cursor: cursor)
  }
}

@MainActor
private final class ScreenProviderSpy: ScreenProviding {
  var screens: [ScreenDescriptor]

  init(screens: [ScreenDescriptor]) {
    self.screens = screens
  }

  func currentScreens() -> [ScreenDescriptor] {
    screens
  }
}

@MainActor
private final class OverlayPresenterSpy: OverlayPresenting {
  var coveredScreenIDs: Set<UInt32>
  var partialMode = false
  var reconcileCount = 0
  var removeAllCount = 0
  private(set) var lastReconciledScreenIDs: Set<UInt32> = []
  init(coveredScreenIDs: Set<UInt32> = []) {
    self.coveredScreenIDs = coveredScreenIDs
    partialMode = !coveredScreenIDs.isEmpty
  }

  func reconcile(with screens: [ScreenDescriptor]) {
    reconcileCount += 1
    lastReconciledScreenIDs = Set(screens.map(\.id))
    if !partialMode {
      coveredScreenIDs = lastReconciledScreenIDs
    }
  }

  func removeAll() {
    removeAllCount += 1
    coveredScreenIDs = []
  }
}

@MainActor
private final class HotKeyRegistrarSpy: HotKeyRegistering {
  let primaryRegistrationSucceeds: Bool
  let emergencyRegistrationSucceeds: Bool
  private(set) var isPrimaryRegistered: Bool
  private(set) var unregisterEmergencyEscapeCount = 0
  private(set) var emergencyEscapeHandler: (() -> Void)?

  init(primaryRegistrationSucceeds: Bool = true, emergencyRegistrationSucceeds: Bool = true) {
    self.primaryRegistrationSucceeds = primaryRegistrationSucceeds
    self.emergencyRegistrationSucceeds = emergencyRegistrationSucceeds
    self.isPrimaryRegistered = primaryRegistrationSucceeds
  }

  func registerPrimary(_ shortcut: KeyboardShortcut, handler: @escaping () -> Void) throws {
    guard primaryRegistrationSucceeds else { throw HotKeyError.unavailable }
    isPrimaryRegistered = true
  }

  func registerEmergencyEscape(handler: @escaping () -> Void) throws {
    guard emergencyRegistrationSucceeds else { throw HotKeyError.unavailable }
    emergencyEscapeHandler = handler
  }

  func unregisterEmergencyEscape() {
    unregisterEmergencyEscapeCount += 1
  }
}

@MainActor
private final class CursorSpy: CursorManaging {
  private(set) var hideCount = 0
  private(set) var unhideCount = 0

  func hide() {
    hideCount += 1
  }

  func unhide() {
    unhideCount += 1
  }
}

private enum HotKeyError: Error {
  case unavailable
}

private extension ScreenDescriptor {
  init(id: UInt32) {
    self.init(id: id, frame: .zero)
  }
}
