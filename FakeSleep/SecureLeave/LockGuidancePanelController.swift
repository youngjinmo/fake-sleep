import AppKit
import SwiftUI

@MainActor
final class LockGuidanceViewModel: ObservableObject {
  @Published private(set) var countdown: Int

  init(countdown: Int = 60) {
    self.countdown = max(0, countdown)
  }

  func setCountdown(_ countdown: Int) {
    self.countdown = max(0, countdown)
  }
}

struct LockGuidanceView: View {
  @ObservedObject var viewModel: LockGuidanceViewModel
  let onCancel: () -> Void
  let onOpenSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Image(systemName: "lock.shield")
        .font(.system(size: 36))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      Text(Self.localized("secureLeave.guidance.title", fallback: "Your Mac stays awake"))
        .font(.title2.weight(.semibold))

      Text(
        Self.localized(
          "secureLeave.guidance.message",
          fallback: "Press the keys below to lock your Mac. Your work will continue while it is locked."
        )
      )
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        keycap("⌃", label: Self.localized("secureLeave.key.control", fallback: "Control"))
        Text("+")
          .foregroundStyle(.secondary)
        keycap("⌘", label: Self.localized("secureLeave.key.command", fallback: "Command"))
        Text("+")
          .foregroundStyle(.secondary)
        keycap("Q", label: "Q")
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        Self.localized(
          "secureLeave.guidance.shortcut",
          fallback: "Press Control Command Q to lock your Mac"
        )
      )

      Text(
        String(
          format: Self.localized(
            "secureLeave.guidance.countdown",
            fallback: "Waiting for the lock screen · %d seconds remaining"
          ),
          viewModel.countdown
        )
      )
      .font(.callout.monospacedDigit())
      .foregroundStyle(.secondary)
      .accessibilityValue("\(viewModel.countdown)")

      HStack(spacing: 12) {
        Button(
          Self.localized("secureLeave.guidance.cancel", fallback: "Cancel Session"),
          action: onCancel
        )
        .keyboardShortcut(.cancelAction)

        Button(
          Self.localized(
            "secureLeave.guidance.openSettings",
            fallback: "Open Lock Screen Settings"
          ),
          action: onOpenSettings
        )
        .buttonStyle(.link)
      }
    }
    .padding(28)
    .frame(minWidth: 440)
  }

  private func keycap(_ value: String, label: String) -> some View {
    Text(value)
      .font(.system(size: 24, weight: .medium, design: .rounded))
      .frame(minWidth: 48, minHeight: 42)
      .background(
        RoundedRectangle(cornerRadius: 7)
          .fill(Color(nsColor: .controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7)
          .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
      )
      .accessibilityLabel(label)
  }

  private static func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
  }
}

@MainActor
final class LockGuidancePanelController: NSWindowController, NSWindowDelegate {
  private(set) var viewModel: LockGuidanceViewModel
  private weak var coordinator: FakeSleepCoordinator?
  private let settingsHandler: () -> Void
  private var stateObserverID: UUID?
  private var countdownTimer: Timer?
  private var isClosingInternally = false
  private var isPreparedForTermination = false

  var countdownRemaining: Int { viewModel.countdown }

  init(
    coordinator: FakeSleepCoordinator,
    settingsHandler: @escaping () -> Void = { LockScreenSettingsOpener().open() }
  ) {
    self.coordinator = coordinator
    self.settingsHandler = settingsHandler
    self.viewModel = LockGuidanceViewModel()
    super.init(window: nil)

    stateObserverID = coordinator.addStateObserver { [weak self] state in
      self?.handleStateChange(state)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func open() {
    guard !isPreparedForTermination else { return }
    guard let coordinator, coordinator.state == .awaitingSystemLock else {
      close()
      return
    }

    if window == nil {
      window = makeWindow()
    }
    refresh()
    guard let window else { return }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func refresh() {
    guard let coordinator else { return }
    viewModel.setCountdown(Int(ceil(coordinator.lockCountdownRemaining)))
  }

  func cancel() {
    coordinator?.endSession(reason: .manual)
  }

  func openLockScreenSettings() {
    settingsHandler()
  }

  override func close() {
    countdownTimer?.invalidate()
    countdownTimer = nil
    guard let window else { return }

    isClosingInternally = true
    window.delegate = nil
    window.close()
    self.window = nil
    isClosingInternally = false
  }

  func prepareForTermination() {
    guard !isPreparedForTermination else { return }
    isPreparedForTermination = true
    countdownTimer?.invalidate()
    countdownTimer = nil
    if let stateObserverID {
      coordinator?.removeStateObserver(stateObserverID)
      self.stateObserverID = nil
    }
    close()
  }

  func windowWillClose(_ notification: Notification) {
    guard !isClosingInternally,
          let closingWindow = notification.object as? NSWindow,
          closingWindow === window else {
      return
    }

    window = nil
    coordinator?.endSession(reason: .manual)
  }

  private func handleStateChange(_ state: FakeSleepState) {
    switch state {
    case .awaitingSystemLock:
      open()
      startCountdownTimer()
    case .inactive, .active, .preparingBlackout, .awake, .fakeSleeping:
      close()
    }
  }

  private func makeWindow() -> NSPanel {
    let contentView = NSHostingView(
      rootView: LockGuidanceView(
        viewModel: viewModel,
        onCancel: { [weak self] in self?.cancel() },
        onOpenSettings: { [weak self] in self?.openLockScreenSettings() }
      )
    )
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 330),
      styleMask: [.titled, .closable, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.title = NSLocalizedString(
      "secureLeave.guidance.title",
      bundle: .main,
      value: "Your Mac stays awake",
      comment: ""
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.contentView = contentView
    panel.delegate = self
    panel.center()
    return panel
  }

  private func startCountdownTimer() {
    guard countdownTimer == nil else { return }
    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.refresh()
      }
    }
  }
}

@MainActor
final class LockScreenSettingsOpener {
  func open() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}

typealias SecureLeaveGuideController = LockGuidancePanelController
typealias SecureLeaveGuidanceView = LockGuidanceView
