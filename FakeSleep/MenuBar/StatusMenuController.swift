import AppKit

@MainActor
protocol CurrentTimeProviding {
  var now: Date { get }
}

@MainActor
final class SystemCurrentTimeProvider: CurrentTimeProviding {
  var now: Date { Date() }
}

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
  let statusItem: NSStatusItem
  private(set) var statusImageName = "moon"
  private(set) var durationMenu: NSMenu?

  private let statusBar: NSStatusBar
  private weak var coordinator: FakeSleepCoordinator?
  private let settingsStore: SessionSettingsStore
  private let settingsChangedHandler: (() -> Void)?
  private let clock: CurrentTimeProviding
  private let refreshScheduler: SessionScheduling
  private let settingsHandler: () -> Void
  private let userGuideHandler: () -> Void
  private let quitHandler: () -> Void
  private let startHandler: ((SessionConfiguration) -> Void)?
  private var stateObserverID: UUID?
  private var errorObserverID: UUID?
  private var refreshTimer: Timer?
  private var feedbackExpiresAt: Date?
  private var feedbackAcknowledged = false
  private var feedbackExpiryScheduleToken: UUID?
  private var observedEndReason: SessionEndReason?
  private var isClosed = false

  init(
    coordinator: FakeSleepCoordinator,
    settingsHandler: @escaping () -> Void = {},
    userGuideHandler: @escaping () -> Void = {},
    quitHandler: @escaping () -> Void = { NSApp.terminate(nil) },
    statusBar: NSStatusBar = .system,
    settingsStore: SessionSettingsStore = SessionSettingsStore(),
    startHandler: ((SessionConfiguration) -> Void)? = nil,
    settingsChangedHandler: (() -> Void)? = nil,
    clock: CurrentTimeProviding = SystemCurrentTimeProvider(),
    refreshScheduler: SessionScheduling = MonotonicSessionScheduler()
  ) {
    self.coordinator = coordinator
    self.settingsHandler = settingsHandler
    self.userGuideHandler = userGuideHandler
    self.quitHandler = quitHandler
    self.statusBar = statusBar
    self.settingsStore = settingsStore
    self.startHandler = startHandler
    self.settingsChangedHandler = settingsChangedHandler
    self.clock = clock
    self.refreshScheduler = refreshScheduler
    self.statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    stateObserverID = coordinator.addStateObserver { [weak self] _ in
      self?.refresh()
    }
    errorObserverID = coordinator.addErrorObserver { [weak self] _ in
      self?.refresh()
    }
    refresh()
  }

  func close() {
    guard !isClosed else { return }
    isClosed = true
    refreshTimer?.invalidate()
    refreshTimer = nil
    feedbackExpiryScheduleToken = nil

    if let stateObserverID {
      coordinator?.removeStateObserver(stateObserverID)
      self.stateObserverID = nil
    }
    if let errorObserverID {
      coordinator?.removeErrorObserver(errorObserverID)
      self.errorObserverID = nil
    }
    statusItem.menu?.delegate = nil
    statusItem.menu = nil
    statusItem.button?.image = nil
    statusBar.removeStatusItem(statusItem)
  }

  func refresh() {
    guard !isClosed, let coordinator else { return }

    updateFeedbackState(for: coordinator)
    rebuildMenu(for: coordinator)
    updateStatusButton(for: coordinator)
    updateRefreshTimer(for: coordinator)
  }

  func menuWillOpen(_ menu: NSMenu) {
    guard let coordinator else { return }
    if !coordinator.isSessionActive, shouldShowFeedback(for: coordinator.lastEndReason) {
      feedbackAcknowledged = true
    }
    refresh()
  }

  @objc
  private func toggleFakeSleep() {
    guard let coordinator else { return }
    if coordinator.isSessionActive {
      coordinator.endSession(reason: .manual)
      return
    }

    let configuration = settingsStore.settings.configuration
    if let startHandler {
      startHandler(configuration)
    } else {
      // Keep the original menu action source-compatible for clients that do
      // not inject the new settings-aware start path.
      coordinator.toggle()
    }
  }

  @objc
  private func startSecureLeave() {
    start(mode: .secureLeave)
  }

  @objc
  private func startBlackout() {
    start(mode: .blackout)
  }

  @objc
  private func endSession() {
    coordinator?.endSession(reason: .manual)
  }

  @objc
  private func cancelBlackoutPreparation() {
    coordinator?.cancelBlackoutPreparation()
  }

  @objc
  private func selectDuration(_ sender: NSMenuItem) {
    guard let duration = sender.representedObject as? SessionDuration else { return }
    settingsStore.setDuration(duration)
    settingsChangedHandler?()
    refresh()
  }

  @objc
  private func openSettings() {
    settingsHandler()
  }

  @objc
  private func openUserGuide() {
    userGuideHandler()
  }

  @objc
  private func quit() {
    quitHandler()
  }

  private func start(mode: FakeSleepMode) {
    guard let coordinator, !coordinator.isSessionActive else { return }
    let settings = settingsStore.settings
    let configuration = SessionConfiguration(
      mode: mode,
      duration: settings.defaultDuration,
      batteryCutoffPercent: settings.batteryCutoffPercent
    )
    if let startHandler {
      startHandler(configuration)
    } else {
      coordinator.start(configuration: configuration)
    }
  }

  private func rebuildMenu(for coordinator: FakeSleepCoordinator) {
    let menu = statusItem.menu ?? NSMenu()
    menu.autoenablesItems = false
    menu.delegate = self
    menu.removeAllItems()

    let stateItem = menuItem(
      title: stateTitle(for: coordinator),
      action: #selector(toggleFakeSleep),
      enabled: false
    )
    stateItem.toolTip = stateTooltip(for: coordinator)
    stateItem.setAccessibilityLabel(stateTooltip(for: coordinator))
    // The state row is intentionally disabled. Keeping the action preserves
    // the original programmatic toggle entry point for older callers.
    menu.addItem(stateItem)

    if coordinator.isSessionActive {
      addActiveItems(to: menu, coordinator: coordinator)
    } else {
      addInactiveItems(to: menu)
    }

    statusItem.menu = menu
  }

  private func addInactiveItems(to menu: NSMenu) {
    menu.addItem(
      menuItem(
        title: localized("menu.startSecureLeave", fallback: "Safely Leave"),
        action: #selector(startSecureLeave)
      )
    )
    menu.addItem(
      menuItem(
        title: blackoutStartTitle(),
        action: #selector(startBlackout)
      )
    )
    menu.addItem(.separator())
    menu.addItem(makeDurationMenuItem())
    addCommonItems(to: menu, includeSeparatorBeforeQuit: true)
  }

  private func addActiveItems(to menu: NSMenu, coordinator: FakeSleepCoordinator) {
    let modeItem = menuItem(
      title: activeModeTitle(for: coordinator.currentSession?.mode),
      action: nil,
      enabled: false
    )
    modeItem.setAccessibilityLabel(modeItem.title)
    menu.addItem(modeItem)

    let timeItem = menuItem(
      title: activeTimeTitle(for: coordinator),
      action: nil,
      enabled: false
    )
    timeItem.setAccessibilityLabel(timeItem.title)
    menu.addItem(timeItem)

    if coordinator.state == .preparingBlackout {
      let localizedTitle = localized("menu.cancelBlackoutPreparation", fallback: "Cancel")
      let title = localizedTitle.localizedCaseInsensitiveContains("cancel")
        ? localizedTitle
        : "\(localizedTitle) (Cancel)"
      let cancelItem = menuItem(
        title: title,
        action: #selector(cancelBlackoutPreparation)
      )
      cancelItem.setAccessibilityLabel(cancelItem.title)
      menu.addItem(cancelItem)
    }

    let batteryItem = menuItem(
      title: batteryTitle(for: coordinator.currentSession?.batteryCutoffPercent),
      action: nil,
      enabled: false
    )
    batteryItem.setAccessibilityLabel(batteryItem.title)
    menu.addItem(batteryItem)

    let endItem = menuItem(
      title: localized("menu.endSession", fallback: "End Session"),
      action: #selector(endSession)
    )
    endItem.setAccessibilityLabel(endItem.title)
    menu.addItem(endItem)
    menu.addItem(.separator())
    addCommonItems(to: menu, includeSeparatorBeforeQuit: false)
  }

  private func addCommonItems(to menu: NSMenu, includeSeparatorBeforeQuit: Bool) {
    menu.addItem(
      menuItem(
        title: localized("menu.showUserGuide", fallback: "Show User Guide"),
        action: #selector(openUserGuide)
      )
    )
    menu.addItem(
      menuItem(
        title: localized("menu.settings", fallback: "Settings…"),
        action: #selector(openSettings)
      )
    )
    if includeSeparatorBeforeQuit {
      menu.addItem(.separator())
    }
    menu.addItem(
      menuItem(
        title: localized("menu.quitFakeSleep", fallback: "Quit Fake Sleep"),
        action: #selector(quit)
      )
    )
  }

  private func blackoutStartTitle() -> String {
    let title = localized("menu.startBlackout", fallback: "Blackout Only")
    let warning = localized(
      "mode.blackout.warning",
      fallback: "Mac is not locked. This mode is not a security feature."
    )
    return "\(title) · \(warning)"
  }

  private func makeDurationMenuItem() -> NSMenuItem {
    let submenu = NSMenu()
    submenu.autoenablesItems = false
    let selectedDuration = settingsStore.settings.defaultDuration
    for duration in SessionDuration.presets {
      let item = menuItem(
        title: durationTitle(duration),
        action: #selector(selectDuration(_:))
      )
      item.representedObject = duration
      item.state = duration == selectedDuration ? .on : .off
      item.setAccessibilityLabel(durationTitle(duration))
      submenu.addItem(item)
    }
    durationMenu = submenu

    let item = menuItem(
      title: localized("menu.sessionDuration", fallback: "Session Duration"),
      action: nil
    )
    item.submenu = submenu
    item.setAccessibilityLabel(item.title)
    return item
  }

  private func menuItem(
    title: String,
    action: Selector?,
    enabled: Bool = true
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = enabled
    return item
  }

  private func updateStatusButton(for coordinator: FakeSleepCoordinator) {
    statusImageName = imageName(for: coordinator)
    let image = NSImage(
      systemSymbolName: statusImageName,
      accessibilityDescription: nil
    ) ?? NSImage(size: NSSize(width: 18, height: 18))
    image.setName(statusImageName)
    image.isTemplate = true
    statusItem.button?.image = image
    statusItem.button?.image?.setName(statusImageName)

    let tooltip = stateTooltip(for: coordinator)
    statusItem.button?.setAccessibilityLabel(tooltip)
    statusItem.button?.toolTip = tooltip
  }

  private func updateRefreshTimer(for coordinator: FakeSleepCoordinator) {
    if coordinator.isSessionActive {
      guard refreshTimer == nil else { return }
      refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        Task { @MainActor in
          self?.refresh()
        }
      }
    } else {
      refreshTimer?.invalidate()
      refreshTimer = nil
    }
  }

  private func updateFeedbackState(for coordinator: FakeSleepCoordinator) {
    guard !coordinator.isSessionActive else {
      feedbackExpiresAt = nil
      feedbackAcknowledged = false
      feedbackExpiryScheduleToken = nil
      observedEndReason = nil
      return
    }

    guard let reason = coordinator.lastEndReason,
          shouldShowFeedback(for: reason) else {
      feedbackExpiresAt = nil
      feedbackAcknowledged = false
      feedbackExpiryScheduleToken = nil
      observedEndReason = nil
      return
    }

    if observedEndReason != reason {
      observedEndReason = reason
      feedbackExpiresAt = clock.now.addingTimeInterval(10 * 60)
      feedbackAcknowledged = false
      feedbackExpiryScheduleToken = nil
    }
    if let feedbackExpiresAt, feedbackExpiresAt <= clock.now {
      feedbackAcknowledged = true
      feedbackExpiryScheduleToken = nil
    } else {
      scheduleFeedbackExpiryIfNeeded()
    }
  }

  private func scheduleFeedbackExpiryIfNeeded() {
    guard !feedbackAcknowledged,
          let feedbackExpiresAt else {
      return
    }

    guard feedbackExpiryScheduleToken == nil else { return }
    let token = UUID()
    feedbackExpiryScheduleToken = token
    let interval = max(0, feedbackExpiresAt.timeIntervalSince(clock.now))
    _ = refreshScheduler.schedule(after: interval) { [weak self] in
      guard let self, self.feedbackExpiryScheduleToken == token else { return }
      self.feedbackExpiryScheduleToken = nil
      self.refresh()
    }
  }

  private func imageName(for coordinator: FakeSleepCoordinator) -> String {
    if !coordinator.isSessionActive,
       shouldShowFeedback(for: coordinator.lastEndReason),
       !feedbackAcknowledged {
      return "exclamationmark.triangle"
    }
    return coordinator.isSessionActive ? "moon.fill" : "moon"
  }

  private func stateTitle(for coordinator: FakeSleepCoordinator) -> String {
    guard coordinator.isSessionActive else {
      if let reason = feedbackReasonTitle(for: coordinator),
         !feedbackAcknowledged,
         feedbackExpiresAt.map({ $0 > clock.now }) ?? false {
        return reason
      }
      return localized("menu.startFakeSleep", fallback: "Fake Sleep Off")
    }

    switch coordinator.state {
    case .awaitingSystemLock:
      return secureLeaveLockHint(
        localized("menu.awaitingSystemLock", fallback: "Waiting for Mac to Lock")
      )
    case .preparingBlackout:
      return localized("menu.preparingBlackout", fallback: "Preparing Screen Cover")
    case .active:
      if coordinator.currentSession?.mode == .secureLeave,
         coordinator.currentSession?.lockState != .locked {
        return secureLeaveLockHint(
          localized("menu.unlockedWarning", fallback: "Keeping Mac Awake · Currently Unlocked")
        )
      }
      return localized("menu.restoreDisplays", fallback: "Restore Displays")
    case .inactive, .awake:
      return localized("menu.startFakeSleep", fallback: "Fake Sleep Off")
    case .fakeSleeping:
      return localized("menu.restoreDisplays", fallback: "Restore Displays")
    }
  }

  private func stateTooltip(for coordinator: FakeSleepCoordinator) -> String {
    if coordinator.isSessionActive {
      return "\(stateTitle(for: coordinator)) · \(activeTimeTitle(for: coordinator))"
    }
    return stateTitle(for: coordinator)
  }

  private func secureLeaveLockHint(_ title: String) -> String {
    let hint = localized(
      "menu.lockShortcutHint",
      fallback: "Press ⌃⌘Q to lock before you leave"
    )
    return "\(title) · \(hint)"
  }

  private func activeModeTitle(for mode: FakeSleepMode?) -> String {
    switch mode {
    case .secureLeave:
      return localized("menu.mode.secureLeave", fallback: "Safely Leave")
    case .blackout:
      return localized(
        "menu.mode.blackout",
        fallback: "Blackout Only · Not a Security Feature"
      )
    case nil:
      return localized("menu.active", fallback: "Fake Sleep On")
    }
  }

  private func activeTimeTitle(for coordinator: FakeSleepCoordinator) -> String {
    if coordinator.state == .preparingBlackout {
      return String(
        format: localized(
          "menu.blackoutCountdown",
          fallback: "Screen cover starts in %d seconds"
        ),
        Int(ceil(coordinator.blackoutPreparationRemaining))
      )
    }

    if coordinator.state == .awaitingSystemLock {
      return String(
        format: localized(
          "menu.lockCountdown",
          fallback: "Mac Lock Pending · %d seconds remaining"
        ),
        Int(ceil(coordinator.lockCountdownRemaining))
      )
    }

    if coordinator.currentSession?.monotonicDeadline != nil {
      return String(
        format: localized("menu.remaining", fallback: "%d minutes remaining"),
        displayedMinutes(coordinator.remainingDuration)
      )
    }

    return String(
      format: localized("menu.elapsed", fallback: "Running for %d minutes"),
      displayedMinutes(coordinator.elapsedDuration)
    )
  }

  private func batteryTitle(for cutoff: Int?) -> String {
    guard let cutoff, cutoff > 0 else {
      return localized("menu.batteryDisabled", fallback: "Battery Auto-stop Off")
    }
    return String(
      format: localized(
        "menu.batteryProtection",
        fallback: "Auto-stop at %d%% battery"
      ),
      cutoff
    )
  }

  private func durationTitle(_ duration: SessionDuration) -> String {
    switch duration {
    case .minutes(30):
      return localized("duration.30Minutes", fallback: "30 minutes")
    case .minutes(60):
      return localized("duration.1Hour", fallback: "1 hour")
    case .minutes(120):
      return localized("duration.2Hours", fallback: "2 hours")
    case .minutes(240):
      return localized("duration.4Hours", fallback: "4 hours")
    case .minutes(let minutes):
      return String(
        format: localized("duration.minutes", fallback: "%d minutes"),
        minutes
      )
    case .indefinite:
      return localized("duration.untilStopped", fallback: "Until I stop it")
    }
  }

  private func displayedMinutes(_ interval: TimeInterval) -> Int {
    max(0, Int(interval / 60))
  }

  private func feedbackReasonTitle(for coordinator: FakeSleepCoordinator) -> String? {
    guard let reason = coordinator.lastEndReason else { return nil }
    switch reason {
    case .timerExpired:
      guard let duration = coordinator.lastEndedSessionDuration else {
        return localized("menu.timerEnded", fallback: "Session ended")
      }
      return String(
        format: localized(
          "menu.timerEndedDuration",
          fallback: "%@ session ended"
        ),
        durationTitle(duration)
      )
    case .lowBattery(let percent):
      return String(
        format: localized(
          "menu.batteryEnded",
          fallback: "Automatically stopped at %d%% battery"
        ),
        percent
      )
    case .lockTimedOut:
      return localized("menu.lockTimedOut", fallback: "Session ended · Mac was not locked")
    case .activationFailed:
      return localized("menu.activationFailed", fallback: "Session could not start")
    case .manual:
      return nil
    }
  }

  private func shouldShowFeedback(for reason: SessionEndReason?) -> Bool {
    guard let reason else { return false }
    switch reason {
    case .manual:
      return false
    case .timerExpired, .lowBattery, .lockTimedOut, .activationFailed:
      return true
    }
  }

  private func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
  }
}

@MainActor
extension StatusMenuController {
  convenience init(
    coordinator: FakeSleepCoordinator,
    settingsHandler: @escaping () -> Void = {},
    guideHandler: @escaping () -> Void,
    quitHandler: @escaping () -> Void = { NSApp.terminate(nil) },
    statusBar: NSStatusBar = .system
  ) {
    self.init(
      coordinator: coordinator,
      settingsHandler: settingsHandler,
      userGuideHandler: guideHandler,
      quitHandler: quitHandler,
      statusBar: statusBar
    )
  }
}
