import Foundation

@MainActor
protocol CursorManaging {
  func hide()
  func unhide()
}

@MainActor
protocol FakeSleepCoordinatorProtocol: AnyObject {
  var isSessionActive: Bool { get }
  func start(configuration: SessionConfiguration)
  func endSession(reason: SessionEndReason)
}

@MainActor
final class FakeSleepCoordinator: FakeSleepCoordinatorProtocol {
  private let screenProvider: ScreenProviding
  private let overlayPresenter: OverlayPresenting
  private let hotKeyRegistrar: HotKeyRegistering
  private let cursor: CursorManaging
  private let sleepPreventer: SleepPreventing
  private let powerMonitor: PowerMonitoring
  private let scheduler: SessionScheduling
  private let settingsStore: SessionSettingsStore?
  private let reduceMotion: Bool
  private let onStateChange: ((FakeSleepState) -> Void)?
  private let onErrorChange: ((FakeSleepError?) -> Void)?
  private let defaultConfiguration: SessionConfiguration
  private var stateObservers: [UUID: (FakeSleepState) -> Void] = [:]
  private var errorObservers: [UUID: (FakeSleepError?) -> Void] = [:]

  private var emergencyEscapeRegistered = false
  private var cursorIsHidden = false
  private var monitorIsRunning = false
  private var hasScheduledWork = false
  private var hasCleanedResources = true
  private var activationWarning: FakeSleepError?
  private var sessionMonotonicStart: TimeInterval?
  private var activeSessionDuration: SessionDuration?
  private var lockDeadline: TimeInterval?
  private var blackoutPreparationDeadline: TimeInterval?

  private(set) var state: FakeSleepState = .inactive
  private(set) var error: FakeSleepError?
  private(set) var currentSession: FakeSleepSession?
  private(set) var lastEndReason: SessionEndReason?
  private(set) var lastEndedSessionDuration: SessionDuration?

  var isSessionActive: Bool { state != .inactive }

  var isLocked: Bool {
    currentSession?.lockState == .locked
  }

  var elapsedDuration: TimeInterval {
    guard let sessionMonotonicStart else { return 0 }
    return max(0, scheduler.now - sessionMonotonicStart)
  }

  var remainingDuration: TimeInterval {
    guard let deadline = currentSession?.monotonicDeadline else { return 0 }
    return max(0, deadline - scheduler.now)
  }

  var lockCountdownRemaining: TimeInterval {
    guard state == .awaitingSystemLock,
          let deadline = lockDeadline else {
      return 0
    }
    return max(0, deadline - scheduler.now)
  }

  var blackoutPreparationRemaining: TimeInterval {
    guard state == .preparingBlackout,
          let deadline = blackoutPreparationDeadline else {
      return 0
    }
    return max(0, deadline - scheduler.now)
  }

  init(
    screenProvider: ScreenProviding,
    overlayPresenter: OverlayPresenting,
    hotKeyRegistrar: HotKeyRegistering,
    cursor: CursorManaging,
    sleepPreventer: SleepPreventing = NoopSleepPreventer(),
    powerMonitor: PowerMonitoring = NoopPowerMonitor(),
    scheduler: SessionScheduling = NoopSessionScheduler(),
    settingsStore: SessionSettingsStore? = nil,
    reduceMotion: Bool = false,
    defaultConfiguration: SessionConfiguration = SessionConfiguration(
      mode: .blackout,
      duration: .indefinite,
      batteryCutoffPercent: 0
    ),
    onStateChange: ((FakeSleepState) -> Void)? = nil,
    onErrorChange: ((FakeSleepError?) -> Void)? = nil
  ) {
    self.screenProvider = screenProvider
    self.overlayPresenter = overlayPresenter
    self.hotKeyRegistrar = hotKeyRegistrar
    self.cursor = cursor
    self.sleepPreventer = sleepPreventer
    self.powerMonitor = powerMonitor
    self.scheduler = scheduler
    self.settingsStore = settingsStore
    self.reduceMotion = reduceMotion
    self.defaultConfiguration = defaultConfiguration
    self.onStateChange = onStateChange
    self.onErrorChange = onErrorChange
  }

  func toggle() {
    if state == .inactive {
      start(configuration: defaultConfiguration)
    } else {
      endSession(reason: .manual)
    }
  }

  // Compatibility entry point for the original blackout-only app.
  func activate() {
    start(
      configuration: SessionConfiguration(
        mode: .blackout,
        duration: .indefinite,
        batteryCutoffPercent: 0
      )
    )
  }

  func start(configuration: SessionConfiguration) {
    guard state == .inactive else { return }

    clearErrorForActivation()
    lastEndReason = nil
    lastEndedSessionDuration = nil
    activationWarning = nil
    hasCleanedResources = false

    let normalizedConfiguration = normalized(configuration)
    guard batteryAllowsStart(normalizedConfiguration.batteryCutoffPercent) else {
      let percent = powerMonitor.currentSnapshot.batteryPercent ?? 0
      let reason = SessionEndReason.lowBattery(percent: percent)
      lastEndReason = reason
      updateError(.batteryBelowCutoff(
        percent: percent,
        cutoff: normalizedConfiguration.batteryCutoffPercent
      ))
      hasCleanedResources = true
      return
    }

    let monotonicStart = scheduler.now
    sessionMonotonicStart = monotonicStart
    activeSessionDuration = normalizedConfiguration.duration
    lockDeadline = nil
    let startedAt = Date()
    let durationInterval = normalizedConfiguration.duration.interval
    let deadline = durationInterval.map { monotonicStart + $0 }
    let scheduledEndDate = durationInterval.map { startedAt.addingTimeInterval($0) }
    currentSession = FakeSleepSession(
      mode: normalizedConfiguration.mode,
      startedAt: startedAt,
      monotonicDeadline: deadline,
      scheduledEndDate: scheduledEndDate,
      batteryCutoffPercent: normalizedConfiguration.batteryCutoffPercent
    )

    // The activity is deliberately acquired before any UI or timer work.
    sleepPreventer.begin()
    monitorIsRunning = true
    powerMonitor.start { [weak self] snapshot in
      self?.handlePowerChange(snapshot)
    }

    let emergencyEscapeAvailable = registerEmergencyEscape()
    guard hotKeyRegistrar.isPrimaryRegistered || emergencyEscapeAvailable else {
      failActivation(.noRestorePath)
      return
    }

    if !emergencyEscapeAvailable {
      activationWarning = .emergencyEscapeUnavailable
    }

    switch normalizedConfiguration.mode {
    case .secureLeave:
      beginSecureLeave(deadline: monotonicStart + 60)
    case .blackout:
      beginBlackout()
    }
  }

  func endSession(reason: SessionEndReason) {
    guard hasResourcesToClean else {
      if reason == .manual {
        updateError(nil)
        activationWarning = nil
      }
      return
    }

    lastEndReason = reason
    lastEndedSessionDuration = activeSessionDuration
    let cutoff = currentSession?.batteryCutoffPercent ?? 0
    cleanupResources()
    currentSession = nil
    sessionMonotonicStart = nil
    lockDeadline = nil

    switch reason {
    case .activationFailed(let failure):
      updateError(failure)
    case .lowBattery(let percent):
      updateError(.batteryBelowCutoff(percent: percent, cutoff: cutoff))
    default:
      updateError(nil)
    }
  }

  func cancelBlackoutPreparation() {
    guard state == .preparingBlackout else { return }
    endSession(reason: .manual)
  }

  func restore() {
    guard hasResourcesToClean else {
      updateError(nil)
      activationWarning = nil
      return
    }
    endSession(reason: .manual)
  }

  func handleWorkspaceSessionDidResignActive() {
    guard currentSession?.mode == .secureLeave else { return }

    switch state {
    case .awaitingSystemLock:
      updateLockState(.locked)
      updateState(.active)
    case .active:
      updateLockState(.locked)
    case .inactive, .preparingBlackout, .awake, .fakeSleeping:
      break
    }
  }

  func handleWorkspaceSessionDidBecomeActive() {
    guard state == .active, currentSession?.mode == .secureLeave else { return }
    updateLockState(.unlocked)
  }

  func handleScreenConfigurationChange() {
    reconcileWhileActive()
  }

  func handleWake() {
    if let deadline = currentSession?.monotonicDeadline, scheduler.now >= deadline {
      endSession(reason: .timerExpired)
      return
    }
    reconcileWhileActive()
  }

  func prepareForTermination() {
    guard hasResourcesToClean else { return }
    endSession(reason: .manual)
  }

  @discardableResult
  func addStateObserver(_ observer: @escaping (FakeSleepState) -> Void) -> UUID {
    let id = UUID()
    stateObservers[id] = observer
    observer(state)
    return id
  }

  func removeStateObserver(_ id: UUID) {
    stateObservers.removeValue(forKey: id)
  }

  @discardableResult
  func addErrorObserver(_ observer: @escaping (FakeSleepError?) -> Void) -> UUID {
    let id = UUID()
    errorObservers[id] = observer
    observer(error)
    return id
  }

  func removeErrorObserver(_ id: UUID) {
    errorObservers.removeValue(forKey: id)
  }

  private func beginSecureLeave(deadline: TimeInterval) {
    lockDeadline = deadline
    updateState(.awaitingSystemLock)
    schedule(after: max(0, deadline - scheduler.now)) { [weak self] in
      guard let self, self.state == .awaitingSystemLock else { return }
      self.endSession(reason: .lockTimedOut)
    }
    scheduleSessionExpiration()
  }

  private func beginBlackout() {
    guard shouldPrepareBlackout else {
      activateBlackout()
      return
    }

    let deadline = scheduler.now + 3
    blackoutPreparationDeadline = deadline
    updateState(.preparingBlackout)
    schedule(after: 3) { [weak self] in
      guard let self, self.state == .preparingBlackout else { return }
      self.blackoutPreparationDeadline = nil
      self.activateBlackout()
    }
  }

  private var shouldPrepareBlackout: Bool {
    settingsStore?.isBlackoutSafetyIntroShown == false
  }

  private func activateBlackout() {

    let screens = screenProvider.currentScreens()
    guard !screens.isEmpty else {
      failActivation(.noScreens)
      return
    }

    overlayPresenter.reconcile(with: screens)
    guard hasCompleteCoverage(for: screens) else {
      failActivation(.incompleteOverlayCoverage)
      return
    }

    cursor.hide()
    cursorIsHidden = true
    updateState(.active)

    let isFirstBlackoutUse = shouldPrepareBlackout
    if isFirstBlackoutUse {
      settingsStore?.setBlackoutSafetyIntroShown(true)
    }
    showRestoreHint(shouldScheduleDismissal: isFirstBlackoutUse || reduceMotion)

    scheduleSessionExpiration()
    updateError(activationWarning)
  }

  private func showRestoreHint(shouldScheduleDismissal: Bool) {
    overlayPresenter.setRestoreHintVisible(true, animated: !reduceMotion)
    guard shouldScheduleDismissal else { return }
    schedule(after: 2) { [weak self] in
      guard let self, self.state == .active else { return }
      self.overlayPresenter.setRestoreHintVisible(false, animated: !self.reduceMotion)
    }
  }

  private func scheduleSessionExpiration() {
    guard let deadline = currentSession?.monotonicDeadline else { return }

    schedule(after: max(0, deadline - scheduler.now)) { [weak self] in
      guard let self,
            let currentDeadline = self.currentSession?.monotonicDeadline else {
        return
      }

      guard self.scheduler.now >= currentDeadline else {
        self.scheduleSessionExpiration()
        return
      }
      self.endSession(reason: .timerExpired)
    }
  }

  private func failActivation(_ failure: FakeSleepError) {
    endSession(reason: .activationFailed(failure))
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

  private func reconcileWhileActive() {
    guard state == .active, currentSession?.mode == .blackout else { return }

    let screens = screenProvider.currentScreens()
    guard !screens.isEmpty else {
      failActivation(.noScreens)
      return
    }

    overlayPresenter.reconcile(with: screens)
    guard hasCompleteCoverage(for: screens) else {
      failActivation(.incompleteOverlayCoverage)
      return
    }
    updateError(activationWarning)
  }

  private func handlePowerChange(_ snapshot: PowerSnapshot) {
    guard state != .inactive,
          snapshot.isUsingBattery,
          let percent = snapshot.batteryPercent,
          let cutoff = currentSession?.batteryCutoffPercent,
          cutoff > 0,
          percent <= cutoff else {
      return
    }
    endSession(reason: .lowBattery(percent: percent))
  }

  private func batteryAllowsStart(_ cutoff: Int) -> Bool {
    guard cutoff > 0 else { return true }
    let snapshot = powerMonitor.currentSnapshot
    guard snapshot.isUsingBattery else { return true }
    guard let percent = snapshot.batteryPercent else { return true }
    return percent > cutoff
  }

  private func normalized(_ configuration: SessionConfiguration) -> SessionConfiguration {
    SessionConfiguration(
      mode: configuration.mode,
      duration: normalizedDuration(configuration.duration),
      batteryCutoffPercent: (0...100).contains(configuration.batteryCutoffPercent)
        ? configuration.batteryCutoffPercent
        : 10
    )
  }

  private func normalizedDuration(_ duration: SessionDuration) -> SessionDuration {
    switch duration {
    case .indefinite:
      return .indefinite
    case .minutes(let minutes):
      return minutes > 0 ? .minutes(minutes) : .indefinite
    }
  }

  private func schedule(after interval: TimeInterval, _ callback: @escaping () -> Void) {
    _ = scheduler.schedule(after: interval, callback)
    hasScheduledWork = true
  }

  private var hasResourcesToClean: Bool {
    !hasCleanedResources
      || currentSession != nil
      || emergencyEscapeRegistered
      || cursorIsHidden
      || monitorIsRunning
      || hasScheduledWork
      || sleepPreventer.isActive
  }

  private func cleanupResources() {
    guard !hasCleanedResources else { return }
    scheduler.cancel()
    hasScheduledWork = false
    if monitorIsRunning {
      powerMonitor.stop()
      monitorIsRunning = false
    }
    overlayPresenter.removeAll()
    if cursorIsHidden {
      cursor.unhide()
      cursorIsHidden = false
    }
    unregisterEmergencyEscapeIfNeeded()
    sleepPreventer.end()
    updateState(.inactive)
    activationWarning = nil
    sessionMonotonicStart = nil
    activeSessionDuration = nil
    lockDeadline = nil
    blackoutPreparationDeadline = nil
    hasCleanedResources = true
  }

  private func clearErrorForActivation() {
    if error == nil {
      onErrorChange?(nil)
    } else {
      updateError(nil)
    }
  }

  private func updateLockState(_ lockState: SessionLockState) {
    guard var session = currentSession else { return }
    guard session.lockState != lockState else { return }
    session.lockState = lockState
    currentSession = session
    notifyStateObservers()
  }

  private func updateState(_ newState: FakeSleepState) {
    guard state != newState else { return }
    state = newState
    onStateChange?(newState)
    stateObservers.values.forEach { $0(newState) }
  }

  private func notifyStateObservers() {
    stateObservers.values.forEach { $0(state) }
  }

  private func updateError(_ newError: FakeSleepError?) {
    guard error != newError else { return }
    error = newError
    onErrorChange?(newError)
    errorObservers.values.forEach { $0(newError) }
  }

  private func hasCompleteCoverage(for screens: [ScreenDescriptor]) -> Bool {
    let screenIDs = Set(screens.map(\.id))
    return overlayPresenter.coveredScreenIDs == screenIDs
  }
}

@MainActor
final class NoopSleepPreventer: SleepPreventing {
  private(set) var isActive = false

  func begin() { isActive = true }
  func end() { isActive = false }
}

@MainActor
final class NoopPowerMonitor: PowerMonitoring {
  var currentSnapshot = PowerSnapshot(isUsingBattery: false, batteryPercent: nil)
  private var changeHandler: ((PowerSnapshot) -> Void)?

  func start(_ onChange: @escaping (PowerSnapshot) -> Void) {
    changeHandler = onChange
  }

  func stop() {
    changeHandler = nil
  }
}

@MainActor
final class NoopSessionScheduler: SessionScheduling {
  var now: TimeInterval { 0 }

  @discardableResult
  func schedule(after interval: TimeInterval, _ callback: @escaping () -> Void) -> UUID {
    UUID()
  }

  func cancel() {}
}
