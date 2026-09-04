import AppKit

@MainActor
final class AppContainer {
  private let screenProvider: SystemScreenProvider
  private let overlayController: OverlayWindowController
  private let shortcutStore: ShortcutStore
  private let hotKeyRegistrar: HotKeyRegistering
  private let shortcutManager: ShortcutManager
  private let cursor: CursorManaging
  private let sleepPreventer: SleepPreventing
  private let powerMonitor: PowerMonitoring
  private let scheduler: SessionScheduling
  private let sessionSettingsStore: SessionSettingsStore
  private let coordinator: FakeSleepCoordinator
  private let shortcutActionCoordinator: FakeSleepCoordinatorProtocol
  private let loginItemManager: LoginItemManager
  private let settingsViewModel: SettingsViewModel
  private let settingsWindowController: SettingsWindowController
  private let landingWindowController: LandingWindowController
  private let lockGuidanceController: LockGuidancePanelController
  private let workspaceSessionObserver: WorkspaceSessionObserver
  private let statusMenuController: StatusMenuController

  init(
    landingPresentationStore: LandingPresentationStore = LandingPresentationStore(),
    sessionSettingsStore: SessionSettingsStore = SessionSettingsStore(),
    sleepPreventer: SleepPreventing = ProcessInfoSleepPreventer(),
    powerMonitor: PowerMonitoring = IOKitPowerMonitor(),
    scheduler: SessionScheduling = MonotonicSessionScheduler(),
    shortcutCoordinator: FakeSleepCoordinatorProtocol? = nil
  ) {
    let screenProvider = SystemScreenProvider()
    let overlayController = OverlayWindowController()
    let shortcutStore = ShortcutStore()
    let hotKeyRegistrar = CarbonHotKeyController()
    let cursor = SystemCursorAdapter()
    let coordinator = FakeSleepCoordinator(
      screenProvider: screenProvider,
      overlayPresenter: overlayController,
      hotKeyRegistrar: hotKeyRegistrar,
      cursor: cursor,
      sleepPreventer: sleepPreventer,
      powerMonitor: powerMonitor,
      scheduler: scheduler,
      settingsStore: sessionSettingsStore,
      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      defaultConfiguration: sessionSettingsStore.settings.configuration
    )

    self.screenProvider = screenProvider
    self.overlayController = overlayController
    self.shortcutStore = shortcutStore
    self.hotKeyRegistrar = hotKeyRegistrar
    self.cursor = cursor
    self.sleepPreventer = sleepPreventer
    self.powerMonitor = powerMonitor
    self.scheduler = scheduler
    self.sessionSettingsStore = sessionSettingsStore
    self.coordinator = coordinator
    self.shortcutActionCoordinator = shortcutCoordinator ?? coordinator

    let shortcutActionCoordinator = shortcutCoordinator ?? coordinator
    let shortcutManager = ShortcutManager(
      store: shortcutStore,
      registrar: hotKeyRegistrar,
      handler: { @MainActor [weak shortcutActionCoordinator] in
        guard let shortcutActionCoordinator else { return }
        if shortcutActionCoordinator.isSessionActive {
          shortcutActionCoordinator.endSession(reason: .manual)
        } else {
          shortcutActionCoordinator.start(configuration: sessionSettingsStore.settings.configuration)
        }
      }
    )
    self.shortcutManager = shortcutManager

    overlayController.onScreenConfigurationChange = { @MainActor [weak coordinator] in
      coordinator?.handleScreenConfigurationChange()
    }
    overlayController.onWake = { @MainActor [weak coordinator] in
      coordinator?.handleWake()
    }
    overlayController.setRestoreHandler { @MainActor [weak coordinator] in
      coordinator?.restore()
    }

    shortcutManager.registerOnLaunch()

    let loginItemManager = LoginItemManager()
    let settingsViewModel = SettingsViewModel(
      shortcutManager: shortcutManager,
      loginItemManager: loginItemManager,
      coordinator: coordinator,
      settingsStore: sessionSettingsStore
    )
    let settingsWindowController = SettingsWindowController(viewModel: settingsViewModel)
    let lockGuidanceController = LockGuidancePanelController(
      coordinator: coordinator,
      settingsHandler: { @MainActor [weak settingsViewModel] in
        settingsViewModel?.openLockScreenSettings()
      }
    )
    let workspaceSessionObserver = WorkspaceSessionObserver(coordinator: coordinator)
    let landingViewModel = LandingViewModel(
      coordinator: coordinator,
      settingsViewModel: settingsViewModel,
      presentationStore: landingPresentationStore,
      settingsStore: sessionSettingsStore,
      settingsHandler: { @MainActor [weak settingsWindowController] in
        settingsWindowController?.open()
      }
    )
    let landingWindowController = LandingWindowController(
      viewModel: landingViewModel,
      coordinator: coordinator
    )
    let statusMenuController = StatusMenuController(
      coordinator: coordinator,
      settingsHandler: { @MainActor [weak settingsWindowController] in
        settingsWindowController?.open()
      },
      userGuideHandler: { @MainActor [weak landingWindowController] in
        landingWindowController?.open()
      },
      settingsStore: sessionSettingsStore,
      startHandler: { @MainActor [weak coordinator] configuration in
        coordinator?.start(configuration: configuration)
      },
      settingsChangedHandler: { @MainActor [weak settingsViewModel] in
        settingsViewModel?.refreshSettings()
      }
    )

    self.loginItemManager = loginItemManager
    self.settingsViewModel = settingsViewModel
    self.settingsWindowController = settingsWindowController
    self.landingWindowController = landingWindowController
    self.lockGuidanceController = lockGuidanceController
    self.workspaceSessionObserver = workspaceSessionObserver
    self.statusMenuController = statusMenuController

    landingWindowController.openAtLaunchIfNeeded()
  }

  func prepareForTermination() {
    workspaceSessionObserver.stop()
    lockGuidanceController.prepareForTermination()
    coordinator.prepareForTermination()
    if shortcutActionCoordinator.isSessionActive {
      shortcutActionCoordinator.endSession(reason: .manual)
    }
    landingWindowController.prepareForTermination()
    settingsWindowController.close()
    statusMenuController.close()
  }

  convenience init(coordinator: FakeSleepCoordinatorProtocol) {
    self.init(shortcutCoordinator: coordinator)
  }

  func invokeShortcutAction() {
    if shortcutActionCoordinator.isSessionActive {
      shortcutActionCoordinator.endSession(reason: .manual)
    } else {
      shortcutActionCoordinator.start(configuration: sessionSettingsStore.settings.configuration)
    }
  }
}

@MainActor
private final class WorkspaceSessionObserver {
  private let notificationCenter: NotificationCenter
  private weak var coordinator: FakeSleepCoordinator?
  private var observers: [NSObjectProtocol] = []

  init(
    coordinator: FakeSleepCoordinator,
    notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
  ) {
    self.coordinator = coordinator
    self.notificationCenter = notificationCenter
    observers.append(
      notificationCenter.addObserver(
        forName: NSWorkspace.sessionDidResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.coordinator?.handleWorkspaceSessionDidResignActive()
        }
      }
    )
    observers.append(
      notificationCenter.addObserver(
        forName: NSWorkspace.sessionDidBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.coordinator?.handleWorkspaceSessionDidBecomeActive()
        }
      }
    )
  }

  func stop() {
    observers.forEach { notificationCenter.removeObserver($0) }
    observers.removeAll()
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
