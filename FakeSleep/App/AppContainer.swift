import AppKit

@MainActor
final class AppContainer {
  private let screenProvider: SystemScreenProvider
  private let overlayController: OverlayWindowController
  private let shortcutStore: ShortcutStore
  private let hotKeyRegistrar: HotKeyRegistering
  private let shortcutManager: ShortcutManager
  private let cursor: CursorManaging
  private let coordinator: FakeSleepCoordinator
  private let loginItemManager: LoginItemManager
  private let settingsViewModel: SettingsViewModel
  private let settingsWindowController: SettingsWindowController
  private let statusMenuController: StatusMenuController

  init() {
    let screenProvider = SystemScreenProvider()
    let overlayController = OverlayWindowController()
    let shortcutStore = ShortcutStore()
    let hotKeyRegistrar = CarbonHotKeyController()
    let cursor = SystemCursorAdapter()
    let coordinator = FakeSleepCoordinator(
      screenProvider: screenProvider,
      overlayPresenter: overlayController,
      hotKeyRegistrar: hotKeyRegistrar,
      cursor: cursor
    )

    self.screenProvider = screenProvider
    self.overlayController = overlayController
    self.shortcutStore = shortcutStore
    self.hotKeyRegistrar = hotKeyRegistrar
    self.cursor = cursor
    self.coordinator = coordinator

    let shortcutManager = ShortcutManager(
      store: shortcutStore,
      registrar: hotKeyRegistrar,
      handler: { @MainActor [weak coordinator] in
        coordinator?.toggle()
      }
    )
    self.shortcutManager = shortcutManager

    overlayController.onScreenConfigurationChange = { @MainActor [weak coordinator] in
      coordinator?.handleScreenConfigurationChange()
    }
    overlayController.onWake = { @MainActor [weak coordinator] in
      coordinator?.handleWake()
    }

    shortcutManager.registerOnLaunch()

    let loginItemManager = LoginItemManager()
    let settingsViewModel = SettingsViewModel(
      shortcutManager: shortcutManager,
      loginItemManager: loginItemManager,
      coordinator: coordinator
    )
    let settingsWindowController = SettingsWindowController(viewModel: settingsViewModel)
    let statusMenuController = StatusMenuController(
      coordinator: coordinator,
      settingsHandler: { @MainActor [weak settingsWindowController] in
        settingsWindowController?.open()
      }
    )

    self.loginItemManager = loginItemManager
    self.settingsViewModel = settingsViewModel
    self.settingsWindowController = settingsWindowController
    self.statusMenuController = statusMenuController
  }

  func prepareForTermination() {
    coordinator.prepareForTermination()
    settingsWindowController.close()
    statusMenuController.close()
  }
}

@MainActor
private final class SystemCursorAdapter: CursorManaging {
  func hide() {
    NSCursor.hide()
  }

  func unhide() {
    NSCursor.unhide()
  }
}
