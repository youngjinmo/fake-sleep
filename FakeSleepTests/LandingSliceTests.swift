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

  func test온보딩로그인시작실패는원래nil단축키와설정을원자적으로롤백한다() {
    // Given: 기존 단축키가 nil이고 로그인 항목 변경이 실패하는 상태다.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let settingsStore = SessionSettingsStore(defaults: defaults)
    let registrar = LandingHotKeyRegisteringFake()
    let shortcutManager = ShortcutManager(
      store: ShortcutStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
      registrar: registrar,
      handler: {}
    )
    let loginItemManager = LandingLoginItemManagingFake()
    loginItemManager.setEnabledError = LandingLoginItemError.operationFailed
    let settingsViewModel = SettingsViewModel(
      shortcutManager: shortcutManager,
      loginItemManager: loginItemManager,
      coordinator: nil,
      settingsStore: settingsStore
    )
    let presentationStore = LandingPresentationStore(defaults: defaults)
    let viewModel = LandingViewModel(
      coordinator: makeCoordinator(),
      settingsViewModel: settingsViewModel,
      presentationStore: presentationStore,
      settingsStore: settingsStore
    )
    let customShortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command])
    viewModel.beginOnboarding()
    viewModel.setDraftShortcut(customShortcut)
    viewModel.setLaunchAtLogin(true)
    _ = viewModel.next()
    _ = viewModel.next()

    // When: 로그인 시작까지 포함한 온보딩 완료를 요청한다.
    let didComplete = viewModel.completeOnboarding()

    // Then: 완료되지 않고 원래 nil 단축키와 기존 설정으로 복구된다.
    XCTAssertFalse(didComplete)
    XCTAssertNil(settingsViewModel.shortcut)
    XCTAssertEqual(settingsViewModel.sessionSettings, SessionSettingsStore.defaultSettings)
    XCTAssertFalse(settingsViewModel.loginItemStatus == .enabled)
    XCTAssertFalse(presentationStore.isOnboardingCompleted)
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
  func testlegacy표시안함값과무관하게미완료온보딩은자동으로열리고수동으로다시열수있다() {
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

    // Given: 이전 버전에서 앱 실행 시 랜딩을 표시하지 않도록 저장되어 있다.
    viewModel.setShowsAtLaunch(false)
    XCTAssertFalse(viewModel.showsAtLaunch)

    // When: 새 온보딩이 완료되지 않은 상태에서 앱 실행 자동 열기를 요청한다.
    let didOpenAtLaunch = controller.openAtLaunchIfNeeded()

    // Then: legacy 표시 안 함 값은 무시되고 온보딩 창이 열린다.
    XCTAssertTrue(didOpenAtLaunch)
    XCTAssertNotNil(controller.window)

    // When: 사용자가 창을 닫은 뒤 메뉴에서 랜딩을 수동으로 다시 연다.
    controller.close()
    controller.open()

    // Then: 수동 열기는 완료 버전과 무관하게 창을 만든다.
    XCTAssertNotNil(controller.window)

    controller.prepareForTermination()
  }

  func test온보딩버전1완료후자동열기는건너뛰고수동열기는된다() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let presentationStore = LandingPresentationStore(defaults: defaults)
    presentationStore.markOnboardingCompleted()
    let coordinator = makeCoordinator()
    let viewModel = makeViewModel(
      coordinator: coordinator,
      presentationStore: presentationStore,
      settingsStore: presentationStore.settingsStore
    )
    let controller = LandingWindowController(viewModel: viewModel, coordinator: coordinator)

    // Given: 현재 온보딩 버전 1이 완료되어 있다.
    XCTAssertFalse(viewModel.shouldShowOnboarding)

    // When: 앱 실행 자동 열기와 메뉴의 수동 열기를 차례로 요청한다.
    let didOpenAtLaunch = controller.openAtLaunchIfNeeded()
    controller.open()

    // Then: 자동 열기는 건너뛰지만 수동 열기는 가능하다.
    XCTAssertFalse(didOpenAtLaunch)
    XCTAssertNotNil(controller.window)

    controller.prepareForTermination()
  }

  func test온보딩완료후창닫기취소경로가저장된설정과완료버전을되돌리지않는다() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let presentationStore = LandingPresentationStore(defaults: defaults)
    let settingsStore = presentationStore.settingsStore
    let coordinator = makeCoordinator()
    let settingsViewModel = makeSettingsViewModel(settingsStore: settingsStore)
    let viewModel = LandingViewModel(
      coordinator: coordinator,
      settingsViewModel: settingsViewModel,
      presentationStore: presentationStore,
      settingsStore: settingsStore
    )
    let controller = LandingWindowController(viewModel: viewModel, coordinator: coordinator)
    controller.open()

    // Given: 온보딩에서 기본 설정을 변경하고 마지막 단계까지 이동했다.
    viewModel.setMode(.blackout)
    viewModel.setDuration(.minutes(120))
    viewModel.setBatteryCutoffPercent(0)
    _ = viewModel.next()
    _ = viewModel.next()

    // When: 온보딩을 완료한다. 완료 callback은 창을 닫으며 취소 경로도 호출한다.
    let didComplete = viewModel.completeOnboarding()

    // Then: 저장된 설정과 완료 버전은 취소 경로에 의해 되돌아가지 않는다.
    XCTAssertTrue(didComplete)
    XCTAssertEqual(settingsStore.settings.defaultMode, .blackout)
    XCTAssertEqual(settingsStore.settings.defaultDuration, .minutes(120))
    XCTAssertEqual(settingsStore.settings.batteryCutoffPercent, 0)
    XCTAssertEqual(settingsStore.onboardingVersion, 1)

    controller.prepareForTermination()
  }

  func test온보딩창을취소하면작성중인초안은저장되지않는다() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let presentationStore = LandingPresentationStore(defaults: defaults)
    let settingsStore = presentationStore.settingsStore
    let originalSettings = settingsStore.settings
    let coordinator = makeCoordinator()
    let viewModel = LandingViewModel(
      coordinator: coordinator,
      settingsViewModel: makeSettingsViewModel(settingsStore: settingsStore),
      presentationStore: presentationStore,
      settingsStore: settingsStore
    )
    let controller = LandingWindowController(viewModel: viewModel, coordinator: coordinator)
    controller.open()

    // Given: 사용자가 온보딩 초안을 수정했지만 아직 완료하지 않았다.
    viewModel.setMode(.blackout)
    viewModel.setDuration(.minutes(240))
    viewModel.setBatteryCutoffPercent(100)

    // When: 창을 닫아 온보딩을 취소한다.
    controller.close()

    // Then: 초안과 완료 버전은 저장되지 않고 기존 설정이 유지된다.
    XCTAssertEqual(settingsStore.settings, originalSettings)
    XCTAssertEqual(settingsStore.onboardingVersion, 0)
    XCTAssertNil(controller.window)

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
    let presentationStore = makePresentationStore()
    return makeViewModel(
      coordinator: coordinator,
      presentationStore: presentationStore,
      settingsStore: presentationStore.settingsStore
    )
  }

  private func makeViewModel(
    coordinator: FakeSleepCoordinator,
    presentationStore: LandingPresentationStore,
    settingsStore: SessionSettingsStore
  ) -> LandingViewModel {
    LandingViewModel(
      coordinator: coordinator,
      settingsViewModel: makeSettingsViewModel(settingsStore: settingsStore),
      presentationStore: presentationStore,
      settingsStore: settingsStore
    )
  }

  private func makeSettingsViewModel(
    settingsStore: SessionSettingsStore = SessionSettingsStore(
      defaults: UserDefaults(suiteName: UUID().uuidString)!
    )
  ) -> SettingsViewModel {
    let shortcutManager = ShortcutManager(
      store: ShortcutStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
      registrar: LandingHotKeyRegisteringFake(),
      handler: {}
    )
    shortcutManager.registerOnLaunch()

    return SettingsViewModel(
      shortcutManager: shortcutManager,
      loginItemManager: LandingLoginItemManagingFake(),
      coordinator: nil,
      settingsStore: settingsStore
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
  private(set) var status: LoginItemStatus
  var setEnabledError: Error?

  init(status: LoginItemStatus = .disabled) {
    self.status = status
  }

  func refreshStatus() {}

  func setEnabled(_ enabled: Bool) throws {
    if let setEnabledError {
      throw setEnabledError
    }
    status = enabled ? .enabled : .disabled
  }

  func openSystemSettings() {}
}

private enum LandingLoginItemError: Error {
  case operationFailed
}

private enum LandingHotKeyRegistrationError: Error {
  case unavailable
}
