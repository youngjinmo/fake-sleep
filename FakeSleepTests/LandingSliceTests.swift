import AppKit
import Foundation
import XCTest
@testable import FakeSleep

@MainActor
final class LandingViewModelTests: XCTestCase {
  func test설정ViewModel의단축키변경을최신shortcut으로반영한다() {
    let coordinator = makeCoordinator()
    let settingsViewModel = makeSettingsViewModel()
    let viewModel = LandingViewModel(
      coordinator: coordinator,
      settingsViewModel: settingsViewModel,
      presentationStore: makePresentationStore()
    )
    let customShortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command])

    // Given: 랜딩 view model이 설정 view model의 현재 단축키를 사용하고 있다.
    XCTAssertEqual(viewModel.shortcut, settingsViewModel.shortcut)

    // When: 설정 화면에서 유효한 사용자 단축키를 저장한다.
    settingsViewModel.setShortcut(customShortcut)

    // Then: 랜딩이 최신 사용자 단축키를 노출한다.
    XCTAssertEqual(viewModel.shortcut, customShortcut)
  }

  func test랜딩활성화성공시코디네이터를fakeSleeping으로바꾸고창을닫는다() {
    let coordinator = makeCoordinator()
    let viewModel = makeViewModel(coordinator: coordinator)
    let controller = LandingWindowController(viewModel: viewModel, coordinator: coordinator)
    controller.open()

    // Given: 랜딩 창이 열려 있고 연결된 화면이 있다.
    XCTAssertNotNil(controller.window)
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertFalse(viewModel.isFakeSleeping)

    // When: 랜딩의 화면 어둡게 하기 action을 실행한다.
    viewModel.activate()

    // Then: 활성화에 성공하고 랜딩 창은 자동으로 닫힌다.
    XCTAssertEqual(coordinator.state, .fakeSleeping)
    XCTAssertTrue(viewModel.isFakeSleeping)
    XCTAssertNil(controller.window)

    controller.prepareForTermination()
  }

  func test화면이없어활성화에실패하면noScreens오류와창을유지한다() {
    let coordinator = makeCoordinator(screens: [])
    let viewModel = makeViewModel(coordinator: coordinator)
    let controller = LandingWindowController(viewModel: viewModel, coordinator: coordinator)
    controller.open()
    let landingWindow = controller.window

    // Given: 랜딩 창이 열려 있지만 연결된 화면이 없다.
    XCTAssertNotNil(landingWindow)

    // When: 랜딩의 화면 어둡게 하기 action을 실행한다.
    viewModel.activate()

    // Then: noScreens 오류를 노출하고 랜딩 창은 유지한다.
    XCTAssertEqual(viewModel.error, .noScreens)
    XCTAssertEqual(coordinator.state, .awake)
    XCTAssertFalse(viewModel.isFakeSleeping)
    XCTAssertTrue(controller.window === landingWindow)

    controller.prepareForTermination()
  }

  func testopenSettings는설정콜백을호출한다() {
    let coordinator = makeCoordinator()
    var settingsOpenCount = 0
    let viewModel = LandingViewModel(
      coordinator: coordinator,
      settingsViewModel: makeSettingsViewModel(),
      presentationStore: makePresentationStore(),
      settingsHandler: { settingsOpenCount += 1 }
    )

    // Given: 설정 열기 callback이 랜딩 view model에 주입되어 있다.
    XCTAssertEqual(settingsOpenCount, 0)

    // When: 랜딩에서 설정 열기를 요청한다.
    viewModel.openSettings()

    // Then: 주입된 설정 열기 callback이 한 번 호출된다.
    XCTAssertEqual(settingsOpenCount, 1)
  }

  private func makeViewModel(coordinator: FakeSleepCoordinator) -> LandingViewModel {
    LandingViewModel(
      coordinator: coordinator,
      settingsViewModel: makeSettingsViewModel(),
      presentationStore: makePresentationStore()
    )
  }

  private func makeSettingsViewModel() -> SettingsViewModel {
    let shortcutManager = ShortcutManager(
      store: ShortcutStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
      registrar: LandingHotKeyRegisteringFake(),
      handler: {}
    )
    shortcutManager.registerOnLaunch()

    return SettingsViewModel(
      shortcutManager: shortcutManager,
      loginItemManager: LandingLoginItemManagingFake(),
      coordinator: nil
    )
  }

  private func makePresentationStore() -> LandingPresentationStore {
    LandingPresentationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  }

  private func makeCoordinator(
    screens: [ScreenDescriptor] = [ScreenDescriptor(id: 1, frame: .zero)]
  ) -> FakeSleepCoordinator {
    FakeSleepCoordinator(
      screenProvider: LandingScreenProvidingFake(screens: screens),
      overlayPresenter: LandingOverlayPresentingFake(),
      hotKeyRegistrar: LandingHotKeyRegisteringFake(),
      cursor: LandingCursorManagingFake()
    )
  }
}

@MainActor
final class LandingWindowControllerTests: XCTestCase {
  func testshowsAtLaunch가꺼져있어도자동열기는건너뛰고수동열기는된다() {
    let coordinator = makeCoordinator()
    let presentationStore = LandingPresentationStore(
      defaults: UserDefaults(suiteName: UUID().uuidString)!
    )
    let viewModel = LandingViewModel(
      coordinator: coordinator,
      settingsViewModel: makeSettingsViewModel(),
      presentationStore: presentationStore
    )
    let controller = LandingWindowController(viewModel: viewModel, coordinator: coordinator)

    // Given: 앱 실행 시 랜딩을 표시하지 않도록 저장되어 있다.
    viewModel.setShowsAtLaunch(false)
    XCTAssertFalse(viewModel.showsAtLaunch)

    // When: 앱 실행 시 랜딩을 자동으로 열도록 요청한다.
    controller.openAtLaunchIfNeeded()

    // Then: 자동 열기는 저장된 설정에 따라 건너뛴다.
    XCTAssertNil(controller.window)

    // When: 사용자가 메뉴에서 랜딩을 수동으로 연다.
    controller.open()

    // Then: 수동 열기는 자동 표시 설정과 무관하게 창을 만든다.
    XCTAssertNotNil(controller.window)

    controller.prepareForTermination()
  }

  func test창을닫으면window참조를비우고다시열때새창을생성한다() {
    let coordinator = makeCoordinator()
    let viewModel = makeViewModel(coordinator: coordinator)
    let controller = LandingWindowController(viewModel: viewModel, coordinator: coordinator)

    // Given: 랜딩 창을 한 번 열었다.
    controller.open()
    let firstWindow = controller.window
    XCTAssertNotNil(firstWindow)
    XCTAssertTrue(controller.viewModel === viewModel)

    // When: 랜딩 창을 닫는다.
    controller.close()

    // Then: controller가 닫힌 창을 더 이상 참조하지 않는다.
    XCTAssertNil(controller.window)

    // When: 랜딩 창을 다시 연다.
    controller.open()
    let secondWindow = controller.window

    // Then: 새 NSWindow가 생성되고 이전 창과 identity가 다르다.
    XCTAssertNotNil(secondWindow)
    XCTAssertFalse(firstWindow === secondWindow)

    controller.prepareForTermination()
  }

  func test코디네이터를직접활성화해도열린랜딩창을닫는다() {
    let coordinator = makeCoordinator()
    let viewModel = makeViewModel(coordinator: coordinator)
    let controller = LandingWindowController(viewModel: viewModel, coordinator: coordinator)
    controller.open()

    // Given: 전역 단축키가 처리될 때 랜딩 창이 열려 있다.
    XCTAssertNotNil(controller.window)

    // When: 전역 단축키가 호출하는 코디네이터 activation 경로를 직접 실행한다.
    coordinator.activate()

    // Then: 가짜 슬립이 시작되면 랜딩 창이 자동으로 닫힌다.
    XCTAssertEqual(coordinator.state, .fakeSleeping)
    XCTAssertTrue(viewModel.isFakeSleeping)
    XCTAssertNil(controller.window)

    controller.prepareForTermination()
  }

  private func makeViewModel(coordinator: FakeSleepCoordinator) -> LandingViewModel {
    LandingViewModel(
      coordinator: coordinator,
      settingsViewModel: makeSettingsViewModel(),
      presentationStore: makePresentationStore()
    )
  }

  private func makeSettingsViewModel() -> SettingsViewModel {
    let shortcutManager = ShortcutManager(
      store: ShortcutStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
      registrar: LandingHotKeyRegisteringFake(),
      handler: {}
    )
    shortcutManager.registerOnLaunch()

    return SettingsViewModel(
      shortcutManager: shortcutManager,
      loginItemManager: LandingLoginItemManagingFake(),
      coordinator: nil
    )
  }

  private func makePresentationStore() -> LandingPresentationStore {
    LandingPresentationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  }

  private func makeCoordinator(
    screens: [ScreenDescriptor] = [ScreenDescriptor(id: 1, frame: .zero)]
  ) -> FakeSleepCoordinator {
    FakeSleepCoordinator(
      screenProvider: LandingScreenProvidingFake(screens: screens),
      overlayPresenter: LandingOverlayPresentingFake(),
      hotKeyRegistrar: LandingHotKeyRegisteringFake(),
      cursor: LandingCursorManagingFake()
    )
  }
}

@MainActor
private final class LandingScreenProvidingFake: ScreenProviding {
  var screens: [ScreenDescriptor]

  init(screens: [ScreenDescriptor]) {
    self.screens = screens
  }

  func currentScreens() -> [ScreenDescriptor] {
    screens
  }
}

@MainActor
private final class LandingOverlayPresentingFake: OverlayPresenting {
  private(set) var coveredScreenIDs: Set<UInt32> = []

  func reconcile(with screens: [ScreenDescriptor]) {
    coveredScreenIDs = Set(screens.map(\.id))
  }

  func removeAll() {
    coveredScreenIDs = []
  }
}

@MainActor
private final class LandingHotKeyRegisteringFake: HotKeyRegistering {
  var isPrimaryRegistered = true
  var primaryRegistrationSucceeds = true
  var emergencyRegistrationSucceeds = true

  func registerPrimary(_ shortcut: KeyboardShortcut, handler: @escaping () -> Void) throws {
    guard primaryRegistrationSucceeds else {
      isPrimaryRegistered = false
      throw LandingHotKeyRegistrationError.unavailable
    }

    isPrimaryRegistered = true
  }

  func registerEmergencyEscape(handler: @escaping () -> Void) throws {
    guard emergencyRegistrationSucceeds else {
      throw LandingHotKeyRegistrationError.unavailable
    }
  }

  func unregisterEmergencyEscape() {}
}

@MainActor
private final class LandingCursorManagingFake: CursorManaging {
  private(set) var hideCount = 0
  private(set) var unhideCount = 0

  func hide() {
    hideCount += 1
  }

  func unhide() {
    unhideCount += 1
  }
}

@MainActor
private final class LandingLoginItemManagingFake: LoginItemManaging {
  private(set) var status: LoginItemStatus = .disabled

  func refreshStatus() {}

  func setEnabled(_ enabled: Bool) throws {
    status = enabled ? .enabled : .disabled
  }

  func openSystemSettings() {}
}

private enum LandingHotKeyRegistrationError: Error {
  case unavailable
}
