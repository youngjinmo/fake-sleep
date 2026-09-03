import AppKit
import Carbon.HIToolbox

@MainActor
final class AppContainer {
  private let screenProvider: SystemScreenProvider
  private let overlayController: OverlayWindowController
  private let hotKeyRegistrar: HotKeyRegistering
  private let cursor: CursorManaging
  private let coordinator: FakeSleepCoordinator

  init() {
    let screenProvider = SystemScreenProvider()
    let overlayController = OverlayWindowController()
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
    self.hotKeyRegistrar = hotKeyRegistrar
    self.cursor = cursor
    self.coordinator = coordinator

    overlayController.onScreenConfigurationChange = { @MainActor [weak coordinator] in
      coordinator?.handleScreenConfigurationChange()
    }
    overlayController.onWake = { @MainActor [weak coordinator] in
      coordinator?.handleWake()
    }

    let defaultShortcut = KeyboardShortcut(
      keyCode: UInt32(kVK_ANSI_S),
      modifiers: [.command, .option]
    )
    do {
      try hotKeyRegistrar.registerPrimary(defaultShortcut) { @MainActor [weak coordinator] in
        coordinator?.toggle()
      }
    } catch {
      // The coordinator reports the missing restore path when activation is attempted.
    }
  }

  func prepareForTermination() {
    coordinator.prepareForTermination()
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
