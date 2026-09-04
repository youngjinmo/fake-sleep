import SwiftUI

@MainActor
final class LandingViewModel: ObservableObject {
  @Published private(set) var shortcut: KeyboardShortcut?
  @Published private(set) var error: FakeSleepError?
  @Published private(set) var showsAtLaunch: Bool
  @Published private(set) var isFakeSleeping: Bool

  private let coordinator: FakeSleepCoordinator
  private let settingsViewModel: SettingsViewModel
  private let presentationStore: LandingPresentationStore
  private let settingsHandler: () -> Void
  private var shortcutObserverID: UUID?
  private var stateObserverID: UUID?
  private var errorObserverID: UUID?

  init(
    coordinator: FakeSleepCoordinator,
    settingsViewModel: SettingsViewModel,
    presentationStore: LandingPresentationStore,
    settingsHandler: @escaping () -> Void = {}
  ) {
    self.coordinator = coordinator
    self.settingsViewModel = settingsViewModel
    self.presentationStore = presentationStore
    self.settingsHandler = settingsHandler
    self.shortcut = settingsViewModel.shortcut
    self.error = coordinator.error
    self.showsAtLaunch = presentationStore.showsAtLaunch
    self.isFakeSleeping = coordinator.state == .fakeSleeping

    shortcutObserverID = settingsViewModel.addShortcutObserver { [weak self] shortcut in
      self?.shortcut = shortcut
    }
    stateObserverID = coordinator.addStateObserver { [weak self] state in
      self?.isFakeSleeping = state == .fakeSleeping
    }
    errorObserverID = coordinator.addErrorObserver { [weak self] error in
      self?.error = error
    }
  }

  @discardableResult
  func activate() -> Bool {
    guard coordinator.state == .awake else { return false }

    coordinator.activate()
    return coordinator.state == .fakeSleeping
  }

  func openSettings() {
    settingsHandler()
  }

  func setShowsAtLaunch(_ value: Bool) {
    presentationStore.setShowsAtLaunch(value)
    showsAtLaunch = presentationStore.showsAtLaunch
  }

  func prepareForTermination() {
    removeObservers()
  }

  deinit {
    let coordinator = coordinator
    let settingsViewModel = settingsViewModel
    let shortcutObserverID = shortcutObserverID
    let stateObserverID = stateObserverID
    let errorObserverID = errorObserverID

    Task { @MainActor in
      if let shortcutObserverID {
        settingsViewModel.removeShortcutObserver(shortcutObserverID)
      }
      if let stateObserverID {
        coordinator.removeStateObserver(stateObserverID)
      }
      if let errorObserverID {
        coordinator.removeErrorObserver(errorObserverID)
      }
    }
  }

  private func removeObservers() {
    if let shortcutObserverID {
      settingsViewModel.removeShortcutObserver(shortcutObserverID)
      self.shortcutObserverID = nil
    }
    if let stateObserverID {
      coordinator.removeStateObserver(stateObserverID)
      self.stateObserverID = nil
    }
    if let errorObserverID {
      coordinator.removeErrorObserver(errorObserverID)
      self.errorObserverID = nil
    }
  }
}
