import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
  @Published private(set) var shortcut: KeyboardShortcut?
  @Published private(set) var loginItemStatus: LoginItemStatus
  @Published private(set) var error: Error?

  private let shortcutManager: ShortcutManager
  private let loginItemManager: LoginItemManaging
  private weak var coordinator: FakeSleepCoordinator?
  private var coordinatorErrorObserverID: UUID?
  private var shortcutObservers: [UUID: (KeyboardShortcut?) -> Void] = [:]
  private var loginItemError: Error?

  init(
    shortcutManager: ShortcutManager,
    loginItemManager: LoginItemManaging,
    coordinator: FakeSleepCoordinator?
  ) {
    self.shortcutManager = shortcutManager
    self.loginItemManager = loginItemManager
    self.coordinator = coordinator
    self.shortcut = shortcutManager.currentShortcut
    self.loginItemStatus = loginItemManager.status
    self.error = shortcutManager.error

    coordinatorErrorObserverID = coordinator?.addErrorObserver { [weak self] _ in
      self?.refreshError()
    }
  }

  deinit {
    let observerID = coordinatorErrorObserverID
    let coordinator = coordinator
    if let observerID {
      Task { @MainActor in
        coordinator?.removeErrorObserver(observerID)
      }
    }
  }

  @discardableResult
  func addShortcutObserver(_ observer: @escaping (KeyboardShortcut?) -> Void) -> UUID {
    let id = UUID()
    shortcutObservers[id] = observer
    observer(shortcut)
    return id
  }

  func removeShortcutObserver(_ id: UUID) {
    shortcutObservers.removeValue(forKey: id)
  }

  func setShortcut(_ shortcut: KeyboardShortcut) {
    _ = shortcutManager.setShortcut(shortcut)
    updateShortcut()
    refreshError()
  }

  func resetToDefault() {
    _ = shortcutManager.resetToDefault()
    updateShortcut()
    refreshError()
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      try loginItemManager.setEnabled(enabled)
      loginItemStatus = loginItemManager.status
      loginItemError = nil
      refreshError()
    } catch {
      loginItemStatus = loginItemManager.status
      loginItemError = error
      self.error = error
    }
  }

  func refreshLoginItemStatus() {
    loginItemManager.refreshStatus()
    loginItemStatus = loginItemManager.status
    refreshError()
  }

  func openLoginItemSettings() {
    loginItemManager.openSystemSettings()
  }

  private func refreshError() {
    error = shortcutManager.error ?? loginItemError ?? coordinator?.error
  }

  private func updateShortcut() {
    shortcut = shortcutManager.currentShortcut
    shortcutObservers.values.forEach { $0(shortcut) }
  }
}
