import AppKit
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
  @Published private(set) var shortcut: KeyboardShortcut?
  @Published private(set) var loginItemStatus: LoginItemStatus
  @Published private(set) var error: Error?
  @Published private(set) var sessionSettings: SessionSettings
  @Published private(set) var batteryInput: String
  @Published private(set) var batteryValidationError: String?

  private let shortcutManager: ShortcutManager
  private let loginItemManager: LoginItemManaging
  private let settingsStore: SessionSettingsStore
  private weak var coordinator: FakeSleepCoordinator?
  private var coordinatorErrorObserverID: UUID?
  private var coordinatorStateObserverID: UUID?
  private var shortcutObservers: [UUID: (KeyboardShortcut?) -> Void] = [:]
  private var settingsObservers: [UUID: (SessionSettings) -> Void] = [:]
  private var loginItemError: Error?

  init(
    shortcutManager: ShortcutManager,
    loginItemManager: LoginItemManaging,
    coordinator: FakeSleepCoordinator?,
    settingsStore: SessionSettingsStore = SessionSettingsStore()
  ) {
    self.shortcutManager = shortcutManager
    self.loginItemManager = loginItemManager
    self.coordinator = coordinator
    self.settingsStore = settingsStore
    self.shortcut = shortcutManager.currentShortcut
    self.loginItemStatus = loginItemManager.status
    self.sessionSettings = settingsStore.settings
    self.batteryInput = String(settingsStore.settings.batteryCutoffPercent)
    self.batteryValidationError = nil
    self.error = shortcutManager.error

    coordinatorErrorObserverID = coordinator?.addErrorObserver { [weak self] _ in
      self?.refreshError()
    }
    coordinatorStateObserverID = coordinator?.addStateObserver { [weak self] _ in
      self?.objectWillChange.send()
    }
  }

  deinit {
    let observerID = coordinatorErrorObserverID
    let stateObserverID = coordinatorStateObserverID
    let coordinator = coordinator
    if let observerID {
      Task { @MainActor in
        coordinator?.removeErrorObserver(observerID)
        if let stateObserverID {
          coordinator?.removeStateObserver(stateObserverID)
        }
      }
    }
  }

  var defaultMode: FakeSleepMode { sessionSettings.defaultMode }

  var defaultDuration: SessionDuration { sessionSettings.defaultDuration }

  var batteryCutoffPercent: Int { sessionSettings.batteryCutoffPercent }

  var settings: SessionSettings { sessionSettings }

  var configuration: SessionConfiguration { sessionSettings.configuration }

  var isSessionActive: Bool { coordinator?.isSessionActive ?? false }

  var canEditSessionSettings: Bool { !isSessionActive }

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

  @discardableResult
  func addSettingsObserver(_ observer: @escaping (SessionSettings) -> Void) -> UUID {
    let id = UUID()
    settingsObservers[id] = observer
    observer(sessionSettings)
    return id
  }

  func removeSettingsObserver(_ id: UUID) {
    settingsObservers.removeValue(forKey: id)
  }

  func setShortcut(_ shortcut: KeyboardShortcut) {
    guard !isSessionActive else { return }
    _ = shortcutManager.setShortcut(shortcut)
    updateShortcut()
    refreshError()
  }

  func resetToDefault() {
    guard !isSessionActive else { return }
    _ = shortcutManager.resetToDefault()
    updateShortcut()
    refreshError()
  }

  func clearShortcut() {
    guard !isSessionActive else { return }
    shortcutManager.clearShortcut()
    updateShortcut()
    refreshError()
  }

  func setDefaultMode(_ mode: FakeSleepMode) {
    guard !isSessionActive else { return }
    settingsStore.setMode(mode)
    refreshSettings()
  }

  func setMode(_ mode: FakeSleepMode) {
    setDefaultMode(mode)
  }

  func setDefaultDuration(_ duration: SessionDuration) {
    guard !isSessionActive else { return }
    settingsStore.setDuration(duration)
    refreshSettings()
  }

  func setDuration(_ duration: SessionDuration) {
    setDefaultDuration(duration)
  }

  func setBatteryCutoffPercent(_ percent: Int) {
    guard !isSessionActive else { return }
    guard (0...100).contains(percent) else {
      batteryValidationError = localized(
        "settings.battery.invalid",
        fallback: "Enter a battery percentage from 0 to 100."
      )
      return
    }
    batteryValidationError = nil
    batteryInput = String(percent)
    settingsStore.setBatteryCutoffPercent(percent)
    refreshSettings()
  }

  func setBatteryCutoff(_ percent: Int) {
    setBatteryCutoffPercent(percent)
  }

  func setBatteryInput(_ input: String) {
    guard !isSessionActive else { return }
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int(trimmed), (0...100).contains(value) else {
      batteryInput = String(batteryCutoffPercent)
      batteryValidationError = localized(
        "settings.battery.invalid",
        fallback: "Enter a battery percentage from 0 to 100."
      )
      return
    }
    batteryInput = String(value)
    batteryValidationError = nil
    settingsStore.setBatteryCutoffPercent(value)
    refreshSettings()
  }

  func commitBatteryInput() {
    guard !isSessionActive else { return }
    guard let value = Int(batteryInput.trimmingCharacters(in: .whitespacesAndNewlines)),
          (0...100).contains(value) else {
      batteryInput = String(batteryCutoffPercent)
      batteryValidationError = localized(
        "settings.battery.invalid",
        fallback: "Enter a battery percentage from 0 to 100."
      )
      return
    }
    setBatteryCutoffPercent(value)
  }

  func applySessionSettings(_ settings: SessionSettings) {
    guard !isSessionActive else { return }
    settingsStore.save(settings)
    refreshSettings()
  }

  func refreshSettings() {
    sessionSettings = settingsStore.settings
    batteryInput = String(sessionSettings.batteryCutoffPercent)
    settingsObservers.values.forEach { $0(sessionSettings) }
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

  func openLockScreenSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  private func refreshError() {
    error = shortcutManager.error ?? loginItemError ?? coordinator?.error
  }

  private func updateShortcut() {
    shortcut = shortcutManager.currentShortcut
    shortcutObservers.values.forEach { $0(shortcut) }
  }

  private func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
  }
}
