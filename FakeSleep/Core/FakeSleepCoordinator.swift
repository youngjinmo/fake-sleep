@MainActor
protocol CursorManaging {
  func hide()
  func unhide()
}

@MainActor
final class FakeSleepCoordinator {
  private let screenProvider: ScreenProviding
  private let overlayPresenter: OverlayPresenting
  private let hotKeyRegistrar: HotKeyRegistering
  private let cursor: CursorManaging
  private let onStateChange: ((FakeSleepState) -> Void)?
  private let onErrorChange: ((FakeSleepError?) -> Void)?

  private var emergencyEscapeRegistered = false
  private var cursorIsHidden = false
  private var activationWarning: FakeSleepError?

  private(set) var state: FakeSleepState = .awake
  private(set) var error: FakeSleepError?

  init(
    screenProvider: ScreenProviding,
    overlayPresenter: OverlayPresenting,
    hotKeyRegistrar: HotKeyRegistering,
    cursor: CursorManaging,
    onStateChange: ((FakeSleepState) -> Void)? = nil,
    onErrorChange: ((FakeSleepError?) -> Void)? = nil
  ) {
    self.screenProvider = screenProvider
    self.overlayPresenter = overlayPresenter
    self.hotKeyRegistrar = hotKeyRegistrar
    self.cursor = cursor
    self.onStateChange = onStateChange
    self.onErrorChange = onErrorChange
  }

  func toggle() {
    switch state {
    case .awake:
      activate()
    case .fakeSleeping:
      restore()
    }
  }

  func activate() {
    guard state == .awake else { return }

    clearErrorForActivation()
    activationWarning = nil

    let escapeRegistrationSucceeded = registerEmergencyEscape()
    let primaryRegistrationAvailable = hotKeyRegistrar.isPrimaryRegistered

    guard primaryRegistrationAvailable || escapeRegistrationSucceeded else {
      updateError(.noRestorePath)
      return
    }

    if !escapeRegistrationSucceeded {
      activationWarning = .emergencyEscapeUnavailable
    }

    let screens = screenProvider.currentScreens()
    guard !screens.isEmpty else {
      rollbackActivation()
      updateError(.noScreens)
      return
    }

    overlayPresenter.reconcile(with: screens)

    guard hasCompleteCoverage(for: screens) else {
      rollbackActivation()
      updateError(.incompleteOverlayCoverage)
      return
    }

    cursor.hide()
    cursorIsHidden = true
    updateState(.fakeSleeping)
    updateError(activationWarning)
  }

  func restore() {
    let hasActiveResources = state == .fakeSleeping
      || emergencyEscapeRegistered
      || cursorIsHidden

    guard hasActiveResources else {
      updateError(nil)
      activationWarning = nil
      return
    }

    rollbackResources()
    updateError(nil)
    activationWarning = nil
  }

  func handleScreenConfigurationChange() {
    reconcileWhileActive()
  }

  func handleWake() {
    reconcileWhileActive()
  }

  func prepareForTermination() {
    restore()
  }

  private func registerEmergencyEscape() -> Bool {
    do {
      try hotKeyRegistrar.registerEmergencyEscape { [weak self] in
        Task { @MainActor [weak self] in
          self?.restore()
        }
      }
      emergencyEscapeRegistered = true
      return true
    } catch {
      emergencyEscapeRegistered = false
      return false
    }
  }

  private func unregisterEmergencyEscapeIfNeeded() {
    guard emergencyEscapeRegistered else { return }

    hotKeyRegistrar.unregisterEmergencyEscape()
    emergencyEscapeRegistered = false
  }

  private func rollbackActivation() {
    rollbackResources()
  }

  private func reconcileWhileActive() {
    guard state == .fakeSleeping else { return }

    let screens = screenProvider.currentScreens()
    guard !screens.isEmpty else {
      rollbackResources()
      updateError(.noScreens)
      return
    }

    overlayPresenter.reconcile(with: screens)

    guard hasCompleteCoverage(for: screens) else {
      rollbackResources()
      updateError(.incompleteOverlayCoverage)
      return
    }

    updateError(activationWarning)
  }

  private func clearErrorForActivation() {
    if error == nil {
      onErrorChange?(nil)
    } else {
      updateError(nil)
    }
  }

  private func updateState(_ newState: FakeSleepState) {
    guard state != newState else { return }

    state = newState
    onStateChange?(newState)
  }

  private func updateError(_ newError: FakeSleepError?) {
    guard error != newError else { return }

    error = newError
    onErrorChange?(newError)
  }

  private func rollbackResources() {
    overlayPresenter.removeAll()

    if cursorIsHidden {
      cursor.unhide()
      cursorIsHidden = false
    }

    unregisterEmergencyEscapeIfNeeded()
    updateState(.awake)
  }

  private func hasCompleteCoverage(for screens: [ScreenDescriptor]) -> Bool {
    let screenIDs = Set(screens.map(\.id))
    return overlayPresenter.coveredScreenIDs == screenIDs
  }
}
