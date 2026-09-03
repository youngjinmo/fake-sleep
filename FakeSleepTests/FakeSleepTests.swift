import AppKit
import XCTest
@testable import FakeSleep

@MainActor
final class FakeSleepTests: XCTestCase {
  func testAppContainerCanBeCreated() {
    let container = AppContainer()

    XCTAssertNotNil(container)
    container.prepareForTermination()
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

  func test활성중새화면이추가되면전체화면을다시조정한다() {
    let screenProvider = ScreenProviderSpy(screens: [.init(id: 1)])
    let overlayPresenter = OverlayPresenterSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter)

    // Given: 한 화면을 덮은 활성 상태다.
    coordinator.activate()
    screenProvider.screens = [.init(id: 1), .init(id: 2)]

    // When: 화면 구성 변경 콜백을 처리한다.
    coordinator.handleScreenConfigurationChange()

    // Then: 새 화면을 포함한 전체 구성이 한 번 조정된다.
    XCTAssertEqual(overlayPresenter.reconcileCount, 2)
    XCTAssertEqual(overlayPresenter.reconciledIDHistory, [[1], [1, 2]])
    XCTAssertEqual(overlayPresenter.coveredScreenIDs, [1, 2])
  }

  func test활성중화면을제거하면남은화면만조정한다() {
    let screenProvider = ScreenProviderSpy(screens: [.init(id: 1), .init(id: 2)])
    let overlayPresenter = OverlayPresenterSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter)

    // Given: 두 화면을 덮은 활성 상태다.
    coordinator.activate()
    screenProvider.screens = [.init(id: 2)]

    // When: 화면 구성 변경 콜백을 처리한다.
    coordinator.handleScreenConfigurationChange()

    // Then: 남은 화면만 조정 대상으로 전달된다.
    XCTAssertEqual(overlayPresenter.lastReconciledScreenIDs, [2])
    XCTAssertEqual(overlayPresenter.reconciledIDHistory, [[1, 2], [2]])
    XCTAssertEqual(overlayPresenter.coveredScreenIDs, [2])
  }

  func test같은화면구성알림을반복해도중복창생성대상이늘어나지않는다() {
    let screenProvider = ScreenProviderSpy(screens: [.init(id: 1), .init(id: 2)])
    let overlayPresenter = OverlayPresenterSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter)

    // Given: 두 화면을 덮은 활성 상태다.
    coordinator.activate()

    // When: 동일한 화면 구성 알림을 반복한다.
    coordinator.handleScreenConfigurationChange()
    coordinator.handleScreenConfigurationChange()

    // Then: 각 조정의 화면 ID는 동일하며 중복 ID가 생성되지 않는다.
    XCTAssertEqual(overlayPresenter.reconciledIDHistory, [[1, 2], [1, 2], [1, 2]])
    XCTAssertEqual(Set(overlayPresenter.reconciledIDHistory.flatMap { $0 }), [1, 2])
    XCTAssertEqual(overlayPresenter.coveredScreenIDs, [1, 2])
  }

  func test활성중프레임만변경하면갱신된descriptor를전달한다() {
    let original = ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let updated = ScreenDescriptor(id: 1, frame: CGRect(x: 10, y: 20, width: 300, height: 200))
    let screenProvider = ScreenProviderSpy(screens: [original])
    let overlayPresenter = OverlayPresenterSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter)

    // Given: 원래 프레임으로 활성화된 상태다.
    coordinator.activate()
    screenProvider.screens = [updated]

    // When: 화면 구성 변경 콜백을 처리한다.
    coordinator.handleScreenConfigurationChange()

    // Then: 동일 ID에 갱신된 프레임이 전달된다.
    XCTAssertEqual(overlayPresenter.reconciledDescriptors.last, [updated])
  }

  func test깨어있는상태의topology와wake콜백은조정하지않는다() {
    let screenProvider = ScreenProviderSpy(screens: [.init(id: 1)])
    let overlayPresenter = OverlayPresenterSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter)

    // Given: 코디네이터가 깨어 있다.
    // When: topology와 wake 콜백을 호출한다.
    coordinator.handleScreenConfigurationChange()
    coordinator.handleWake()

    // Then: 조정과 창 생성에 해당하는 호출이 없다.
    XCTAssertEqual(overlayPresenter.reconcileCount, 0)
    XCTAssertTrue(overlayPresenter.reconciledIDHistory.isEmpty)
  }

  func testhandleWake는활성상태의현재화면구성을조정한다() {
    let screenProvider = ScreenProviderSpy(screens: [.init(id: 1)])
    let overlayPresenter = OverlayPresenterSpy()
    let coordinator = makeCoordinator(screenProvider: screenProvider, overlayPresenter: overlayPresenter)

    // Given: 활성화 후 현재 화면 구성이 바뀌었다.
    coordinator.activate()
    screenProvider.screens = [.init(id: 2), .init(id: 3)]

    // When: wake 콜백을 처리한다.
    coordinator.handleWake()

    // Then: 현재 화면 ID 전체가 조정된다.
    XCTAssertEqual(overlayPresenter.lastReconciledScreenIDs, [2, 3])
    XCTAssertEqual(overlayPresenter.coveredScreenIDs, [2, 3])
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
final class OverlayWindowFactoryTests: XCTestCase {
  func test실제오버레이창은전체화면을덮는창속성을설정한다() throws {
    let factory = OverlayWindowFactory()
    let frame = CGRect(x: 37, y: 83, width: 321, height: 219)

    // Given: 실제 NSScreen 목록과 무관한 임의의 화면 프레임이 있다.
    // When: 오버레이 창 factory로 창을 생성한다.
    let overlay = try XCTUnwrap(factory.makeWindow(frame: frame) as? NSWindow)
    defer { overlay.close() }

    // Then: 검은색 불투명 borderless screen-saver 창의 계약을 만족한다.
    XCTAssertEqual(overlay.frame, frame)
    XCTAssertTrue(overlay.styleMask.contains(.borderless))
    XCTAssertEqual(overlay.backgroundColor, .black)
    XCTAssertTrue(overlay.isOpaque)
    XCTAssertEqual(overlay.alphaValue, 1)
    XCTAssertFalse(overlay.hasShadow)
    XCTAssertTrue(overlay.ignoresMouseEvents)
    XCTAssertFalse(overlay.isReleasedWhenClosed)
    XCTAssertEqual(overlay.level, .screenSaver)
    XCTAssertTrue(overlay.collectionBehavior.contains(.canJoinAllSpaces))
    XCTAssertTrue(overlay.collectionBehavior.contains(.stationary))
    XCTAssertTrue(overlay.collectionBehavior.contains(.fullScreenAuxiliary))
    XCTAssertTrue(overlay.collectionBehavior.contains(.ignoresCycle))
    XCTAssertEqual(overlay.animationBehavior, .none)
  }

  func test첫창생성실패는covered화면에서제외되고다음조정에서재시도한다() {
    let factory = OverlayWindowFactorySpy(makeWindowResults: [true, false, true])
    let controller = OverlayWindowController(
      factory: factory,
      notificationCenter: NotificationCenter(),
      workspaceNotificationCenter: NotificationCenter()
    )
    let screens = [ScreenDescriptor(id: 1), ScreenDescriptor(id: 2)]

    // Given: 첫 번째 창은 생성되고 두 번째 창은 실패한다.
    controller.reconcile(with: screens)
    XCTAssertEqual(factory.makeWindowFrames.count, 2)
    XCTAssertEqual(controller.coveredScreenIDs, [1])

    // When: 실패했던 두 번째 화면을 포함해 다시 조정한다.
    controller.reconcile(with: screens)

    // Then: 첫 조정에서는 첫 화면만 덮고, 실패 창 생성은 재시도되어 완료된다.
    XCTAssertEqual(factory.makeWindowFrames.count, 3)
    XCTAssertEqual(controller.coveredScreenIDs, [1, 2])
  }

  func test중복화면ID는창을한번만생성한다() {
    let factory = OverlayWindowFactorySpy()
    let controller = OverlayWindowController(
      factory: factory,
      notificationCenter: NotificationCenter(),
      workspaceNotificationCenter: NotificationCenter()
    )
    let duplicateScreens = [
      ScreenDescriptor(id: 7, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
      ScreenDescriptor(id: 7, frame: CGRect(x: 100, y: 0, width: 200, height: 100)),
    ]

    // Given: 동일한 ID를 가진 화면 descriptor가 입력된다.
    // When: 화면 구성을 조정한다.
    controller.reconcile(with: duplicateScreens)

    // Then: 첫 descriptor 기준으로 창을 하나만 생성한다.
    XCTAssertEqual(factory.makeWindowFrames.count, 1)
    XCTAssertEqual(controller.coveredScreenIDs, [7])
  }

  func test주입된알림센터의화면변경과깨움알림을각각한번전달하고해제후전달하지않는다() async {
    let notificationCenter = NotificationCenter()
    let workspaceNotificationCenter = NotificationCenter()
    var screenConfigurationChangeCount = 0
    var wakeCount = 0
    var controller: OverlayWindowController? = OverlayWindowController(
      factory: OverlayWindowFactorySpy(),
      notificationCenter: notificationCenter,
      workspaceNotificationCenter: workspaceNotificationCenter
    )
    controller?.onScreenConfigurationChange = { screenConfigurationChangeCount += 1 }
    controller?.onWake = { wakeCount += 1 }

    // Given: 두 개의 주입된 알림 센터에 observer가 등록되어 있다.
    // When: 화면 변경과 깨움 알림을 각각 게시한다.
    notificationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    await Task.yield()

    // Then: 각 callback이 정확히 한 번 호출된다.
    XCTAssertEqual(screenConfigurationChangeCount, 1)
    XCTAssertEqual(wakeCount, 1)

    // When: controller를 해제한 뒤 같은 알림을 다시 게시한다.
    controller = nil
    notificationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    await Task.yield()

    // Then: teardown된 observer는 callback을 호출하지 않는다.
    XCTAssertEqual(screenConfigurationChangeCount, 1)
    XCTAssertEqual(wakeCount, 1)
  }
}

@MainActor
final class SystemScreenProviderTests: XCTestCase {
  func test화면번호와프레임으로descriptor를생성한다() throws {
    let frame = CGRect(x: 12, y: 34, width: 567, height: 890)

    // Given: UInt32 범위 안의 NSNumber 화면 번호와 임의의 프레임이 있다.
    // When: pure descriptor helper로 descriptor를 만든다.
    let descriptor = try XCTUnwrap(
      SystemScreenProvider.descriptor(screenNumber: NSNumber(value: UInt32.max), frame: frame)
    )

    // Then: 화면 번호는 UInt32로 변환되고 프레임은 그대로 보존된다.
    XCTAssertEqual(descriptor.id, UInt32.max)
    XCTAssertEqual(descriptor.frame, frame)
  }

  func testnil과UInt32범위밖화면번호는descriptor를만들지않는다() {
    let frame = CGRect(x: 1, y: 2, width: 3, height: 4)

    // Given: nil과 UInt32 최대값을 초과한 화면 번호가 있다.
    // When: 각각 descriptor helper에 전달한다.
    let nilDescriptor = SystemScreenProvider.descriptor(screenNumber: nil, frame: frame)
    let outOfRangeDescriptor = SystemScreenProvider.descriptor(
      screenNumber: NSNumber(value: UInt64(UInt32.max) + 1),
      frame: frame
    )

    // Then: 유효하지 않은 화면 번호는 모두 nil이다.
    XCTAssertNil(nilDescriptor)
    XCTAssertNil(outOfRangeDescriptor)
  }
}

@MainActor
final class ShortcutBehaviorTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "FakeSleepTests.ShortcutBehavior.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func test빈저장소는실행시기본단축키를등록하고저장한다() {
    let store = ShortcutStore(defaults: defaults)
    let registrar = HotKeyRegistrarSpy()
    let manager = ShortcutManager(store: store, registrar: registrar, handler: {})

    // Given: 저장된 단축키가 없다.
    // When: 앱 실행 시 단축키를 등록한다.
    manager.registerOnLaunch()

    // Then: Option-Command-S를 등록하고 같은 값이 저장된다.
    XCTAssertEqual(registrar.primaryRegistrations, [.defaultShortcut])
    XCTAssertEqual(store.load(), .defaultShortcut)
    XCTAssertEqual(manager.currentShortcut, .defaultShortcut)
  }

  func test유효한사용자단축키는등록되고저장된다() {
    let store = ShortcutStore(defaults: defaults)
    let registrar = HotKeyRegistrarSpy()
    let manager = ShortcutManager(store: store, registrar: registrar, handler: {})
    let customShortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command])

    // Given: 기본 단축키가 실행 시 등록되어 있다.
    manager.registerOnLaunch()

    // When: 유효한 사용자 단축키로 변경한다.
    let changed = manager.setShortcut(customShortcut)

    // Then: 변경에 성공하고 등록·저장 값이 사용자 단축키다.
    XCTAssertTrue(changed)
    XCTAssertEqual(registrar.primaryRegistrations.last, customShortcut)
    XCTAssertEqual(store.load(), customShortcut)
    XCTAssertEqual(manager.currentShortcut, customShortcut)
    XCTAssertNil(manager.error)
  }

  func test수식키없는단축키는거절되고저장하지않는다() {
    let store = ShortcutStore(defaults: defaults)
    let registrar = HotKeyRegistrarSpy()
    let manager = ShortcutManager(store: store, registrar: registrar, handler: {})
    let invalidShortcut = KeyboardShortcut(keyCode: 0, modifiers: [])

    // Given: 기본 단축키가 저장되어 있다.
    try! store.save(.defaultShortcut)
    manager.registerOnLaunch()

    // When: 수식키가 없는 단축키를 설정한다.
    let changed = manager.setShortcut(invalidShortcut)

    // Then: 설정을 거절하고 기존 값만 유지한다.
    XCTAssertFalse(changed)
    XCTAssertEqual(manager.currentShortcut, .defaultShortcut)
    XCTAssertEqual(store.load(), .defaultShortcut)
    XCTAssertEqual(registrar.primaryRegistrations, [.defaultShortcut])
  }

  func testShift만있는단축키는거절되고저장하지않는다() {
    let store = ShortcutStore(defaults: defaults)
    let registrar = HotKeyRegistrarSpy()
    let manager = ShortcutManager(store: store, registrar: registrar, handler: {})
    let invalidShortcut = KeyboardShortcut(keyCode: 0, modifiers: [.shift])

    // Given: 기본 단축키가 저장되어 있다.
    try! store.save(.defaultShortcut)
    manager.registerOnLaunch()

    // When: Shift만 포함한 단축키를 설정한다.
    let changed = manager.setShortcut(invalidShortcut)

    // Then: 설정을 거절하고 기존 값만 유지한다.
    XCTAssertFalse(changed)
    XCTAssertEqual(manager.currentShortcut, .defaultShortcut)
    XCTAssertEqual(store.load(), .defaultShortcut)
    XCTAssertEqual(registrar.primaryRegistrations, [.defaultShortcut])
  }

  func testEscape녹화는취소되고기본단축키로저장하지않는다() {
    // Given: Escape 키 입력을 녹화기에 전달한다.
    let outcome = ShortcutRecorderLogic.outcome(keyCode: 53, modifiers: [])

    // When: 녹화 결과를 확인한다.
    // Then: Escape는 취소이며 primary 단축키가 될 수 없다.
    guard case .cancelled = outcome else {
      return XCTFail("Escape 녹화는 취소되어야 한다")
    }
    XCTAssertNil(ShortcutStore(defaults: defaults).load())
  }

  func test등록충돌은기존단축키와저장값을유지하고오류를보고한다() {
    let store = ShortcutStore(defaults: defaults)
    let registrar = HotKeyRegistrarSpy()
    let manager = ShortcutManager(store: store, registrar: registrar, handler: {})
    let oldShortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command])
    let newShortcut = KeyboardShortcut(keyCode: 11, modifiers: [.option, .command])

    // Given: 기존 단축키가 등록·저장되어 있고 새 등록은 충돌한다.
    try! store.save(oldShortcut)
    manager.registerOnLaunch()
    registrar.primaryRegistrationSucceeds = false

    // When: 충돌하는 단축키로 변경한다.
    let changed = manager.setShortcut(newShortcut)

    // Then: 변경 실패를 알리고 기존 등록·저장 값을 복원한다.
    XCTAssertFalse(changed)
    XCTAssertEqual(manager.currentShortcut, oldShortcut)
    XCTAssertEqual(store.load(), oldShortcut)
    XCTAssertEqual(registrar.primaryRegistrations, [oldShortcut, newShortcut, oldShortcut])
    XCTAssertNotNil(manager.error)
  }

  func test저장된잘못된키와수식키는기본값으로대체된다() {
    let store = ShortcutStore(defaults: defaults)
    defaults.set(Int(UInt32.max), forKey: "shortcut.keyCode")
    defaults.set(Int(UInt32.max), forKey: "shortcut.modifiers")
    let registrar = HotKeyRegistrarSpy()
    let manager = ShortcutManager(store: store, registrar: registrar, handler: {})

    // Given: 저장소에 허용되지 않은 키와 수식키 비트가 있다.
    // When: 앱 실행 시 저장된 단축키를 읽는다.
    manager.registerOnLaunch()

    // Then: 기본 단축키를 등록하고 저장한다.
    XCTAssertEqual(registrar.primaryRegistrations, [.defaultShortcut])
    XCTAssertEqual(store.load(), .defaultShortcut)
    XCTAssertEqual(manager.currentShortcut, .defaultShortcut)
  }

  func test코디네이터활성화시에만EmergencyEscape를등록하고복원시에해제한다() {
    let registrar = HotKeyRegistrarSpy()
    let coordinator = FakeSleepCoordinator(
      screenProvider: ScreenProviderSpy(screens: [.init(id: 1)]),
      overlayPresenter: OverlayPresenterSpy(),
      hotKeyRegistrar: registrar,
      cursor: CursorSpy()
    )

    // Given: 코디네이터가 깨어 있다.
    XCTAssertEqual(registrar.registerEmergencyEscapeCount, 0)
    XCTAssertEqual(registrar.unregisterEmergencyEscapeCount, 0)

    // When: 가짜 슬립을 활성화한 뒤 복원한다.
    coordinator.activate()
    XCTAssertEqual(registrar.registerEmergencyEscapeCount, 1)
    coordinator.restore()

    // Then: 활성화 중 한 번 등록되고 복원 시 한 번 해제된다.
    XCTAssertEqual(registrar.unregisterEmergencyEscapeCount, 1)
  }
}

@MainActor
final class OverlayWindowControllerTests: XCTestCase {
  func test새화면마다창을하나씩생성한다() {
    let factory = OverlayWindowFactorySpy()
    let controller = OverlayWindowController(
      factory: factory,
      notificationCenter: NotificationCenter(),
      workspaceNotificationCenter: NotificationCenter()
    )

    // Given: 두 화면이 있다.
    let screens = [
      ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
      ScreenDescriptor(id: 2, frame: CGRect(x: 100, y: 0, width: 200, height: 100)),
    ]

    // When: 화면 구성을 조정한다.
    controller.reconcile(with: screens)

    // Then: 화면마다 창 하나가 생성되고 모두 덮인다.
    XCTAssertEqual(factory.makeWindowFrames, screens.map(\.frame))
    XCTAssertEqual(controller.coveredScreenIDs, [1, 2])
    XCTAssertEqual(factory.windows.count, 2)
  }

  func test반복조정은중복창을생성하지않는다() {
    let factory = OverlayWindowFactorySpy()
    let controller = OverlayWindowController(
      factory: factory,
      notificationCenter: NotificationCenter(),
      workspaceNotificationCenter: NotificationCenter()
    )
    let screen = ScreenDescriptor(id: 1, frame: .zero)

    // Given: 한 화면을 조정했다.
    controller.reconcile(with: [screen])

    // When: 동일한 조정을 반복한다.
    controller.reconcile(with: [screen])
    controller.reconcile(with: [screen])

    // Then: 생성 호출과 창 ID가 모두 하나다.
    XCTAssertEqual(factory.makeWindowFrames, [.zero])
    XCTAssertEqual(Set(factory.windows.map(\.id)).count, 1)
    XCTAssertEqual(controller.coveredScreenIDs, [1])
  }

  func test기존화면의프레임을갱신한다() {
    let factory = OverlayWindowFactorySpy()
    let controller = OverlayWindowController(
      factory: factory,
      notificationCenter: NotificationCenter(),
      workspaceNotificationCenter: NotificationCenter()
    )
    let initial = ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let updated = ScreenDescriptor(id: 1, frame: CGRect(x: 10, y: 20, width: 300, height: 200))

    // Given: 기존 화면 창이 있다.
    controller.reconcile(with: [initial])
    let window = try! XCTUnwrap(factory.windows.first)

    // When: 같은 화면의 프레임을 변경한다.
    controller.reconcile(with: [updated])

    // Then: 창을 새로 만들지 않고 프레임만 갱신한다.
    XCTAssertEqual(factory.makeWindowFrames.count, 1)
    XCTAssertEqual(window.frame, updated.frame)
  }

  func test화면연결이끊기면해당창을닫고제거한다() {
    let factory = OverlayWindowFactorySpy()
    let controller = OverlayWindowController(
      factory: factory,
      notificationCenter: NotificationCenter(),
      workspaceNotificationCenter: NotificationCenter()
    )

    // Given: 두 화면의 창이 있다.
    controller.reconcile(with: [.init(id: 1), .init(id: 2)])
    let removedWindow = factory.windows.first { $0.id == 1 }!

    // When: 한 화면의 연결이 끊긴다.
    controller.reconcile(with: [.init(id: 2)])

    // Then: 끊긴 화면의 창만 닫힌다.
    XCTAssertEqual(removedWindow.closeCount, 1)
    XCTAssertEqual(factory.windows.filter { $0.closeCount > 0 }.map(\.id), [1])
    XCTAssertEqual(controller.coveredScreenIDs, [2])
  }

  func testremoveAll은모든창을닫는다() {
    let factory = OverlayWindowFactorySpy()
    let controller = OverlayWindowController(
      factory: factory,
      notificationCenter: NotificationCenter(),
      workspaceNotificationCenter: NotificationCenter()
    )

    // Given: 두 화면의 창이 있다.
    controller.reconcile(with: [.init(id: 1), .init(id: 2)])

    // When: 모든 오버레이를 제거한다.
    controller.removeAll()

    // Then: 모든 창을 닫고 덮은 화면을 비운다.
    XCTAssertTrue(factory.windows.allSatisfy { $0.closeCount == 1 })
    XCTAssertTrue(controller.coveredScreenIDs.isEmpty)
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
  private(set) var reconciledIDHistory: [Set<UInt32>] = []
  private(set) var reconciledDescriptors: [[ScreenDescriptor]] = []
  init(coveredScreenIDs: Set<UInt32> = []) {
    self.coveredScreenIDs = coveredScreenIDs
    partialMode = !coveredScreenIDs.isEmpty
  }

  func reconcile(with screens: [ScreenDescriptor]) {
    reconcileCount += 1
    lastReconciledScreenIDs = Set(screens.map(\.id))
    reconciledIDHistory.append(lastReconciledScreenIDs)
    reconciledDescriptors.append(screens)
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
private final class OverlayWindowSpy: OverlayWindowing {
  let id: UInt32
  var frame: CGRect
  private(set) var orderFrontRegardlessCount = 0
  private(set) var closeCount = 0

  init(id: UInt32, frame: CGRect) {
    self.id = id
    self.frame = frame
  }

  func orderFrontRegardless() {
    orderFrontRegardlessCount += 1
  }

  func close() {
    closeCount += 1
  }
}

@MainActor
private final class OverlayWindowFactorySpy: OverlayWindowCreating {
  private(set) var makeWindowFrames: [CGRect] = []
  private(set) var windows: [OverlayWindowSpy] = []
  private var nextWindowID: UInt32 = 1
  private var makeWindowResults: [Bool]

  init(makeWindowResults: [Bool] = []) {
    self.makeWindowResults = makeWindowResults
  }

  func makeWindow(frame: CGRect) -> OverlayWindowing? {
    makeWindowFrames.append(frame)
    if !makeWindowResults.isEmpty, !makeWindowResults.removeFirst() {
      return nil
    }

    let window = OverlayWindowSpy(id: nextWindowID, frame: frame)
    nextWindowID += 1
    windows.append(window)
    return window
  }
}

@MainActor
private final class HotKeyRegistrarSpy: HotKeyRegistering {
  var primaryRegistrationSucceeds: Bool
  let emergencyRegistrationSucceeds: Bool
  private(set) var isPrimaryRegistered: Bool
  private(set) var primaryRegistrations: [KeyboardShortcut] = []
  private(set) var primaryRegistrationErrors: [Error] = []
  private(set) var registerEmergencyEscapeCount = 0
  private(set) var unregisterEmergencyEscapeCount = 0
  private(set) var emergencyEscapeHandler: (() -> Void)?

  init(primaryRegistrationSucceeds: Bool = true, emergencyRegistrationSucceeds: Bool = true) {
    self.primaryRegistrationSucceeds = primaryRegistrationSucceeds
    self.emergencyRegistrationSucceeds = emergencyRegistrationSucceeds
    self.isPrimaryRegistered = primaryRegistrationSucceeds
  }

  func registerPrimary(_ shortcut: KeyboardShortcut, handler: @escaping () -> Void) throws {
    primaryRegistrations.append(shortcut)
    guard primaryRegistrationSucceeds else {
      primaryRegistrationErrors.append(HotKeyError.unavailable)
      isPrimaryRegistered = false
      throw HotKeyError.unavailable
    }
    isPrimaryRegistered = true
  }

  func registerEmergencyEscape(handler: @escaping () -> Void) throws {
    guard emergencyRegistrationSucceeds else { throw HotKeyError.unavailable }
    registerEmergencyEscapeCount += 1
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
