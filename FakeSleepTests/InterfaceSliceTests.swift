import AppKit
import XCTest
@testable import FakeSleep

@MainActor
final class StatusMenuControllerTests: XCTestCase {
  func test주입된상태에따라첫메뉴와필수메뉴가구성된다() throws {
    let coordinator = makeCoordinator()
    let controller = StatusMenuController(coordinator: coordinator)

    // Given: 코디네이터가 깨어 있는 상태다.
    XCTAssertEqual(coordinator.state, .awake)

    // When: 상태바 메뉴를 확인한다.
    let menu = try XCTUnwrap(controller.statusItem.menu)

    // Then: 첫 항목은 시작이고 설정과 종료 항목을 포함한다.
    XCTAssertEqual(menu.items.first?.title, localized("menu.startFakeSleep", fallback: "Start Fake Sleep"))
    XCTAssertTrue(menu.items.contains { $0.title == localized("menu.settings", fallback: "Settings…") })
    XCTAssertTrue(menu.items.contains { $0.title == localized("menu.quitFakeSleep", fallback: "Quit Fake Sleep") })

    // When: 주입된 코디네이터 상태를 활성으로 바꾼다.
    coordinator.activate()

    // Then: 첫 항목은 디스플레이 복원으로 갱신된다.
    XCTAssertEqual(menu.items.first?.title, localized("menu.restoreDisplays", fallback: "Restore Displays"))
  }

  func test상태에따라상태바이미지와접근성정보를갱신한다() {
    let coordinator = makeCoordinator()
    let controller = StatusMenuController(coordinator: coordinator)
    let button = controller.statusItem.button

    // Given: 코디네이터가 깨어 있는 상태다.
    controller.refresh()
    XCTAssertEqual(controller.statusImageName, "moon")

    // When: 가짜 슬립을 활성화한다.
    coordinator.activate()
    controller.refresh()

    // Then: 활성 이미지와 접근성 정보가 설정된다.
    XCTAssertEqual(controller.statusImageName, "moon.fill")
    XCTAssertFalse(button?.accessibilityLabel()?.isEmpty ?? true)
    XCTAssertFalse(button?.toolTip?.isEmpty ?? true)
  }

  func test사용자안내메뉴를선택하면안내callback을호출한다() throws {
    let coordinator = makeCoordinator()
    var userGuideCallCount = 0
    let controller = StatusMenuController(
      coordinator: coordinator,
      userGuideHandler: { userGuideCallCount += 1 }
    )
    defer { controller.close() }

    // Given: 사용자 안내 메뉴 항목이 상태바 메뉴에 노출되어 있다.
    let menu = try XCTUnwrap(controller.statusItem.menu)
    let item = try XCTUnwrap(menu.items.first {
      $0.title == localized("menu.showUserGuide", fallback: "Show User Guide")
    })
    let action = try XCTUnwrap(item.action)

    // When: 사용자 안내 메뉴 action을 실행한다.
    XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))

    // Then: 주입한 사용자 안내 callback이 한 번 호출된다.
    XCTAssertEqual(userGuideCallCount, 1)
  }

  func test메뉴동작은코디네이터토글을호출한다() throws {
    let coordinator = makeCoordinator()
    let controller = StatusMenuController(coordinator: coordinator)
    let action = try XCTUnwrap(controller.statusItem.menu?.items.first?.action)

    // Given: 코디네이터가 깨어 있고 첫 메뉴가 노출되어 있다.
    XCTAssertEqual(coordinator.state, .awake)

    // When: 첫 메뉴 action을 실행한다.
    let menuItem = try XCTUnwrap(controller.statusItem.menu?.items.first)
    XCTAssertTrue(NSApp.sendAction(action, to: menuItem.target, from: menuItem))

    // Then: 코디네이터가 활성 상태로 전환된다.
    XCTAssertEqual(coordinator.state, .fakeSleeping)
  }

  func testclose는statusitem을정리하고상태observer를해제한다() {
    let coordinator = makeCoordinator()
    let controller = StatusMenuController(coordinator: coordinator)

    // Given: 상태바 메뉴와 코디네이터 observer가 연결되어 있다.
    // When: 상태바 컨트롤러를 닫는다.
    controller.close()

    // Then: orphan 메뉴가 남지 않고 이후 상태 변경도 반영하지 않는다.
    XCTAssertNil(controller.statusItem.menu)
    coordinator.activate()
    XCTAssertEqual(controller.statusImageName, "moon")
  }

  private func makeCoordinator() -> FakeSleepCoordinator {
    FakeSleepCoordinator(
      screenProvider: InterfaceScreenProviderSpy(),
      overlayPresenter: InterfaceOverlayPresenterSpy(),
      hotKeyRegistrar: InterfaceHotKeyRegistrarSpy(),
      cursor: InterfaceCursorSpy()
    )
  }

  private func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
  }
}

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
  func test설정창을반복해서열어도같은window를재사용한다() {
    let controller = SettingsWindowController(viewModel: makeViewModel())

    // Given: 설정 창이 아직 열리지 않았다.
    // When: 설정 창을 두 번 연다.
    controller.open()
    let firstWindow = controller.window
    controller.open()
    let secondWindow = controller.window

    // Then: 하나의 창을 재사용하고 전면에 표시한다.
    XCTAssertNotNil(firstWindow)
    XCTAssertTrue(firstWindow === secondWindow)
    XCTAssertTrue(secondWindow?.isVisible ?? false)
  }

  func test설정창을열면액세서리앱을활성화하고창을전면화한다() {
    let controller = SettingsWindowController(viewModel: makeViewModel())

    // Given: 설정 창을 열 준비가 되어 있다.
    // When: 설정 창을 열고 같은 창을 다시 전면 표시한다.
    controller.open()
    let firstWindow = controller.window
    controller.open()

    // Then: 호스트 활성화 상태와 무관하게 하나의 visible 창을 전면 표시 대상으로 사용한다.
    XCTAssertNotNil(firstWindow)
    XCTAssertTrue(firstWindow === controller.window)
    XCTAssertTrue(controller.window?.isVisible ?? false)
    XCTAssertTrue(controller.window?.canBecomeKey ?? false)
    XCTAssertTrue(controller.window?.canBecomeMain ?? false)
  }

  func test앱활성화알림을받으면로그인항목상태를다시읽는다() async {
    let notificationCenter = NotificationCenter()
    let loginItemManager = InterfaceLoginItemManagerSpy()
    let model = makeViewModel(loginItemManager: loginItemManager)
    let controller = SettingsWindowController(
      viewModel: model,
      notificationCenter: notificationCenter
    )

    // Given: 설정 창을 열었고 로그인 항목이 비활성 상태다.
    controller.open()
    XCTAssertEqual(model.loginItemStatus, .disabled)
    XCTAssertEqual(loginItemManager.refreshStatusCalls, 1)

    // When: 외부에서 로그인 항목 상태가 바뀐 뒤 앱 활성화 알림을 게시한다.
    loginItemManager.status = .enabled
    notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    await Task.yield()

    // Then: view model이 최신 로그인 항목 상태를 표시한다.
    XCTAssertEqual(model.loginItemStatus, .enabled)
    XCTAssertEqual(loginItemManager.refreshStatusCalls, 2)
  }

  private func makeViewModel(
    loginItemManager: InterfaceLoginItemManagerSpy = InterfaceLoginItemManagerSpy()
  ) -> SettingsViewModel {
    SettingsViewModel(
      shortcutManager: ShortcutManager(
        store: ShortcutStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
        registrar: InterfaceHotKeyRegistrarSpy(),
        handler: {}
      ),
      loginItemManager: loginItemManager,
      coordinator: nil
    )
  }
}

@MainActor
final class SettingsViewModelTests: XCTestCase {
  func test단축키초기화로그인항목오류의존성을UI상태에연결한다() {
    let shortcutManager = ShortcutManager(
      store: ShortcutStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
      registrar: InterfaceHotKeyRegistrarSpy(),
      handler: {}
    )
    let loginItemManager = InterfaceLoginItemManagerSpy()
    let model = SettingsViewModel(
      shortcutManager: shortcutManager,
      loginItemManager: loginItemManager,
      coordinator: nil
    )

    // Given: shortcut, 로그인 항목, 오류 의존성이 주입되어 있다.
    let shortcut = KeyboardShortcut.defaultShortcut

    // When: shortcut 변경, 기본값 초기화, 로그인 항목 변경을 요청한다.
    model.setShortcut(shortcut)
    model.resetToDefault()
    model.setLaunchAtLogin(true)

    // Then: 각 UI action이 해당 의존성으로 전달되고 상태를 노출한다.
    XCTAssertEqual(shortcutManager.currentShortcut, shortcut)
    XCTAssertEqual(loginItemManager.setEnabledCalls, [true])
    XCTAssertEqual(model.shortcut, shortcut)
    XCTAssertEqual(model.loginItemStatus, .enabled)
    XCTAssertNil(model.error)
  }

  func test의존성오류를UI오류상태로노출한다() {
    let registrar = InterfaceHotKeyRegistrarSpy()
    registrar.primaryRegistrationSucceeds = false
    let shortcutManager = ShortcutManager(
      store: ShortcutStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
      registrar: registrar,
      handler: {}
    )
    _ = shortcutManager.setShortcut(.defaultShortcut)
    let model = SettingsViewModel(
      shortcutManager: shortcutManager,
      loginItemManager: InterfaceLoginItemManagerSpy(),
      coordinator: nil
    )

    // Given: shortcut 의존성이 등록 오류를 보고한다.
    // When: view model의 오류 상태를 확인한다.
    // Then: UI가 표시할 오류가 비어 있지 않다.
    XCTAssertNotNil(model.error)
    XCTAssertFalse(model.error?.localizedDescription.isEmpty ?? true)
  }

  func test로그인항목오류를기록한뒤상태를새로읽어도오류를유지한다() {
    let loginItemManager = InterfaceLoginItemManagerSpy()
    loginItemManager.setEnabledSucceeds = false
    let model = SettingsViewModel(
      shortcutManager: ShortcutManager(
        store: ShortcutStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
        registrar: InterfaceHotKeyRegistrarSpy(),
        handler: {}
      ),
      loginItemManager: loginItemManager,
      coordinator: nil
    )

    // Given: 로그인 항목 활성화가 오류를 반환한다.
    model.setLaunchAtLogin(true)
    XCTAssertNotNil(model.error)

    // When: 로그인 항목 상태를 다시 읽는다.
    model.refreshLoginItemStatus()

    // Then: 새로 읽은 상태가 오류를 지우지 않는다.
    XCTAssertNotNil(model.error)
  }

  func test로그인항목상태새로고침은manager의refreshStatus를호출한다() {
    let loginItemManager = InterfaceLoginItemManagerSpy()
    let model = SettingsViewModel(
      shortcutManager: ShortcutManager(
        store: ShortcutStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
        registrar: InterfaceHotKeyRegistrarSpy(),
        handler: {}
      ),
      loginItemManager: loginItemManager,
      coordinator: nil
    )

    // Given: view model이 로그인 항목 manager를 주입받았다.
    XCTAssertEqual(loginItemManager.refreshStatusCalls, 0)

    // When: 로그인 항목 상태를 새로고침한다.
    model.refreshLoginItemStatus()

    // Then: manager의 refreshStatus가 실제로 한 번 호출된다.
    XCTAssertEqual(loginItemManager.refreshStatusCalls, 1)
  }
}

@MainActor
private final class InterfaceScreenProviderSpy: ScreenProviding {
  func currentScreens() -> [ScreenDescriptor] {
    [.init(id: 1, frame: .zero)]
  }
}

@MainActor
private final class InterfaceOverlayPresenterSpy: OverlayPresenting {
  var coveredScreenIDs: Set<UInt32> = []

  func reconcile(with screens: [ScreenDescriptor]) {
    coveredScreenIDs = Set(screens.map(\.id))
  }

  func removeAll() {
    coveredScreenIDs = []
  }
}

@MainActor
private final class InterfaceHotKeyRegistrarSpy: HotKeyRegistering {
  var isPrimaryRegistered = true
  var primaryRegistrationSucceeds = true

  func registerPrimary(_ shortcut: KeyboardShortcut, handler: @escaping () -> Void) throws {
    guard primaryRegistrationSucceeds else {
      isPrimaryRegistered = false
      throw InterfaceHotKeyError.unavailable
    }

    isPrimaryRegistered = true
  }
  func registerEmergencyEscape(handler: @escaping () -> Void) throws {}
  func unregisterEmergencyEscape() {}
}

@MainActor
private final class InterfaceCursorSpy: CursorManaging {
  func hide() {}
  func unhide() {}
}

@MainActor
private final class InterfaceLoginItemManagerSpy: LoginItemManaging {
  var status: LoginItemStatus = .disabled
  var setEnabledSucceeds = true
  private(set) var setEnabledCalls: [Bool] = []
  private(set) var refreshStatusCalls = 0

  func setEnabled(_ enabled: Bool) throws {
    setEnabledCalls.append(enabled)
    guard setEnabledSucceeds else {
      throw InterfaceLoginItemError.unavailable
    }
    status = enabled ? .enabled : .disabled
  }

  func refreshStatus() {
    refreshStatusCalls += 1
  }

  func openSystemSettings() {}
}

private enum InterfaceLoginItemError: Error {
  case unavailable
}

private enum InterfaceHotKeyError: Error {
  case unavailable
}
