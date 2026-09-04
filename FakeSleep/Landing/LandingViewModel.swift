import SwiftUI

@MainActor
final class LandingViewModel: ObservableObject {
  static let onboardingStepCount = 3

  static func progressText(step: Int) -> String {
    "\(step)/\(onboardingStepCount)"
  }

  @Published private(set) var shortcut: KeyboardShortcut?
  @Published private(set) var error: FakeSleepError?
  @Published private(set) var showsAtLaunch: Bool
  @Published private(set) var isFakeSleeping: Bool
  @Published private(set) var currentStep = 1
  @Published private(set) var selectedMode: FakeSleepMode
  @Published private(set) var selectedDuration: SessionDuration
  @Published private(set) var selectedBatteryCutoffPercent: Int
  @Published private(set) var batteryInput: String
  @Published private(set) var selectedLaunchAtLogin: Bool
  @Published private(set) var onboardingError: String?
  @Published private(set) var didCompleteOnboarding = false

  private let coordinator: FakeSleepCoordinator
  private let settingsViewModel: SettingsViewModel
  private let presentationStore: LandingPresentationStore
  private let settingsStore: SessionSettingsStore
  private let settingsHandler: () -> Void
  private var shortcutObserverID: UUID?
  private var stateObserverID: UUID?
  private var errorObserverID: UUID?
  private var onboardingCompletionHandler: (() -> Void)?

  init(
    coordinator: FakeSleepCoordinator,
    settingsViewModel: SettingsViewModel,
    presentationStore: LandingPresentationStore,
    settingsStore: SessionSettingsStore? = nil,
    settingsHandler: @escaping () -> Void = {}
  ) {
    self.coordinator = coordinator
    self.settingsViewModel = settingsViewModel
    self.presentationStore = presentationStore
    self.settingsStore = settingsStore ?? presentationStore.settingsStore
    self.settingsHandler = settingsHandler
    self.shortcut = settingsViewModel.shortcut
    self.error = coordinator.error
    self.showsAtLaunch = presentationStore.showsAtLaunch
    self.isFakeSleeping = coordinator.state == .fakeSleeping
    self.selectedMode = settingsViewModel.defaultMode
    self.selectedDuration = settingsViewModel.defaultDuration
    self.selectedBatteryCutoffPercent = settingsViewModel.batteryCutoffPercent
    self.batteryInput = String(settingsViewModel.batteryCutoffPercent)
    self.selectedLaunchAtLogin = settingsViewModel.loginItemStatus == .enabled
    self.onboardingError = nil

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

  var shouldShowOnboarding: Bool {
    presentationStore.shouldShowOnboarding
  }

  var isOnboardingCompleted: Bool {
    presentationStore.isOnboardingCompleted
  }

  var step: Int {
    currentStep
  }

  var onboardingStep: Int {
    currentStep
  }

  var totalSteps: Int {
    Self.onboardingStepCount
  }

  var isFirstStep: Bool {
    currentStep == 1
  }

  var isLastStep: Bool {
    currentStep == Self.onboardingStepCount
  }

  var canGoBack: Bool {
    !isFirstStep
  }

  var canGoNext: Bool {
    !isLastStep
  }

  var mode: FakeSleepMode {
    selectedMode
  }

  var duration: SessionDuration {
    selectedDuration
  }

  var batteryCutoffPercent: Int {
    selectedBatteryCutoffPercent
  }

  var launchAtLogin: Bool {
    selectedLaunchAtLogin
  }

  var selectedShortcut: KeyboardShortcut? {
    shortcut
  }

  var draftSettings: SessionSettings {
    SessionSettings(
      defaultMode: selectedMode,
      defaultDuration: selectedDuration,
      batteryCutoffPercent: selectedBatteryCutoffPercent
    )
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
    // Kept for source compatibility with the original landing screen. The
    // onboarding launch policy is controlled by onboarding.version instead.
    presentationStore.setShowsAtLaunch(value)
    showsAtLaunch = presentationStore.showsAtLaunch
  }

  func setOnboardingCompletionHandler(_ handler: (() -> Void)?) {
    onboardingCompletionHandler = handler
  }

  func beginOnboarding() {
    let settings = settingsViewModel.sessionSettings
    currentStep = 1
    selectedMode = settings.defaultMode
    selectedDuration = settings.defaultDuration
    selectedBatteryCutoffPercent = settings.batteryCutoffPercent
    batteryInput = String(settings.batteryCutoffPercent)
    selectedLaunchAtLogin = settingsViewModel.loginItemStatus == .enabled
    shortcut = settingsViewModel.shortcut
    onboardingError = nil
    didCompleteOnboarding = false
  }

  func startOnboarding() {
    beginOnboarding()
  }

  @discardableResult
  func next() -> Bool {
    guard currentStep < Self.onboardingStepCount else { return false }
    currentStep += 1
    return true
  }

  @discardableResult
  func previous() -> Bool {
    guard currentStep > 1 else { return false }
    currentStep -= 1
    return true
  }

  @discardableResult
  func goToNextStep() -> Bool {
    next()
  }

  @discardableResult
  func goToPreviousStep() -> Bool {
    previous()
  }

  func setMode(_ mode: FakeSleepMode) {
    selectedMode = mode
    onboardingError = nil
  }

  func setSelectedMode(_ mode: FakeSleepMode) {
    setMode(mode)
  }

  func setDuration(_ duration: SessionDuration) {
    guard SessionDuration.presets.contains(duration) else { return }
    selectedDuration = duration
    onboardingError = nil
  }

  func setSelectedDuration(_ duration: SessionDuration) {
    setDuration(duration)
  }

  func setBatteryCutoffPercent(_ percent: Int) {
    guard (0...100).contains(percent) else {
      onboardingError = Self.localized(
        "onboarding.battery.invalid",
        fallback: "Enter a battery percentage from 0 to 100."
      )
      return
    }
    selectedBatteryCutoffPercent = percent
    batteryInput = String(percent)
    onboardingError = nil
  }

  func setSelectedBatteryCutoffPercent(_ percent: Int) {
    setBatteryCutoffPercent(percent)
  }

  func setBatteryInput(_ input: String) {
    batteryInput = input
    guard let value = validBatteryValue(in: input) else {
      onboardingError = Self.localized(
        "onboarding.battery.invalid",
        fallback: "Enter a battery percentage from 0 to 100."
      )
      return
    }
    selectedBatteryCutoffPercent = value
    onboardingError = nil
  }

  @discardableResult
  func commitBatteryInput() -> Bool {
    guard let value = validBatteryValue(in: batteryInput) else {
      batteryInput = String(selectedBatteryCutoffPercent)
      onboardingError = Self.localized(
        "onboarding.battery.invalid",
        fallback: "Enter a battery percentage from 0 to 100."
      )
      return false
    }
    setBatteryCutoffPercent(value)
    return true
  }

  func adjustBatteryCutoff(by amount: Int) {
    setBatteryCutoffPercent(selectedBatteryCutoffPercent + amount)
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    selectedLaunchAtLogin = enabled
    onboardingError = nil
  }

  func setSelectedLaunchAtLogin(_ enabled: Bool) {
    setLaunchAtLogin(enabled)
  }

  func setDraftShortcut(_ shortcut: KeyboardShortcut) {
    do {
      try ShortcutValidator.validate(shortcut)
      self.shortcut = shortcut
      onboardingError = nil
    } catch let error as ShortcutValidationError {
      onboardingError = error.localizedDescription
    } catch {
      onboardingError = Self.localized(
        "onboarding.shortcut.invalid",
        fallback: "Choose a valid shortcut."
      )
    }
  }

  func setSelectedShortcut(_ shortcut: KeyboardShortcut) {
    setDraftShortcut(shortcut)
  }

  @discardableResult
  func completeOnboarding() -> Bool {
    guard isLastStep, commitBatteryInput() else { return false }

    let originalSettings = settingsViewModel.sessionSettings
    let originalShortcut = settingsViewModel.shortcut
    let originalLaunchAtLogin = settingsViewModel.loginItemStatus == .enabled
    let settings = draftSettings

    settingsViewModel.applySessionSettings(settings)
    guard settingsViewModel.sessionSettings == settings else {
      onboardingError = Self.localized(
        "onboarding.completion.failed",
        fallback: "Settings could not be saved. Try again."
      )
      return false
    }

    if let shortcut, shortcut != originalShortcut {
      settingsViewModel.setShortcut(shortcut)
      guard settingsViewModel.shortcut == shortcut else {
        rollback(
          settings: originalSettings,
          shortcut: originalShortcut,
          launchAtLogin: originalLaunchAtLogin
        )
        onboardingError = Self.localized(
          "onboarding.completion.failed",
          fallback: "Settings could not be saved. Try again."
        )
        return false
      }
    }

    if selectedLaunchAtLogin != originalLaunchAtLogin {
      settingsViewModel.setLaunchAtLogin(selectedLaunchAtLogin)
      guard isLaunchAtLoginApplied else {
        rollback(
          settings: originalSettings,
          shortcut: originalShortcut,
          launchAtLogin: originalLaunchAtLogin
        )
        onboardingError = Self.localized(
          "onboarding.completion.failed",
          fallback: "Settings could not be saved. Try again."
        )
        return false
      }
    }

    settingsStore.markOnboardingCompleted()
    didCompleteOnboarding = true
    onboardingError = nil
    let completionHandler = onboardingCompletionHandler
    completionHandler?()
    didCompleteOnboarding = true
    return true
  }

  @discardableResult
  func complete() -> Bool {
    completeOnboarding()
  }

  func cancelOnboarding() {
    settingsStore.cancelOnboarding()
    beginOnboarding()
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

  private var isLaunchAtLoginApplied: Bool {
    if selectedLaunchAtLogin {
      return settingsViewModel.loginItemStatus == .enabled
    }
    return settingsViewModel.loginItemStatus == .disabled
  }

  private func rollback(
    settings: SessionSettings,
    shortcut: KeyboardShortcut?,
    launchAtLogin: Bool
  ) {
    settingsViewModel.applySessionSettings(settings)
    if let shortcut, settingsViewModel.shortcut != shortcut {
      settingsViewModel.setShortcut(shortcut)
    } else if shortcut == nil, settingsViewModel.shortcut != nil {
      settingsViewModel.clearShortcut()
    }
    if selectedLaunchAtLogin != launchAtLogin {
      settingsViewModel.setLaunchAtLogin(launchAtLogin)
    }
  }

  private func validBatteryValue(in input: String) -> Int? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int(trimmed), (0...100).contains(value) else {
      return nil
    }
    return value
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

  private static func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
  }
}
