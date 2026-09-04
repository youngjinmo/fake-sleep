import SwiftUI

struct SettingsView: View {
  @ObservedObject var viewModel: SettingsViewModel

  var body: some View {
    Form {
      defaultBehaviorSection
      powerSection
      shortcutSection

      if let error = viewModel.error {
        Text(error.localizedDescription)
          .foregroundStyle(.red)
          .font(.callout)
          .accessibilityLabel(error.localizedDescription)
      }
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 520)
  }

  private var defaultBehaviorSection: some View {
    Section(
      header: Text(Self.localized("settings.section.defaultBehavior", fallback: "Default Behavior"))
    ) {
      Picker(
        Self.localized("settings.defaultMode", fallback: "Default mode"),
        selection: Binding(
          get: { viewModel.defaultMode.rawValue },
          set: { rawValue in
            guard let mode = FakeSleepMode(rawValue: rawValue) else { return }
            viewModel.setDefaultMode(mode)
          }
        )
      ) {
        Text(Self.localized("mode.secureLeave", fallback: "Safely Leave · Recommended"))
          .tag(FakeSleepMode.secureLeave.rawValue)
        Text(Self.localized("mode.blackout", fallback: "Blackout Only"))
          .tag(FakeSleepMode.blackout.rawValue)
      }
      .disabled(viewModel.isSessionActive)

      if viewModel.defaultMode == .blackout {
        Text(
          Self.localized(
            "mode.blackout.warning",
            fallback: "Mac is not locked. This mode is not a security feature."
          )
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      }

      Picker(
        Self.localized("settings.sessionDuration", fallback: "Session duration"),
        selection: Binding(
          get: { durationKey(viewModel.defaultDuration) },
          set: { key in
            guard let duration = duration(forKey: key) else { return }
            viewModel.setDefaultDuration(duration)
          }
        )
      ) {
        ForEach(SessionDuration.presets, id: \.selfKey) { duration in
          Text(durationLabel(duration)).tag(durationKey(duration))
        }
      }
      .disabled(viewModel.isSessionActive)

      HStack(alignment: .top, spacing: 10) {
        Button(
          Self.localized(
            "settings.openLockScreenSettings",
            fallback: "Open macOS Lock Screen Settings"
          )
        ) {
          viewModel.openLockScreenSettings()
        }
        Text(
          Self.localized(
            "settings.displaySleepFollowsSystem",
            fallback: "Display sleep timing follows macOS settings."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var powerSection: some View {
    Section(
      header: Text(Self.localized("settings.section.power", fallback: "Power & Battery"))
    ) {
      HStack(spacing: 8) {
        Text(Self.localized("settings.batteryCutoffPrefix", fallback: "Automatically stop at"))
        TextField(
          Self.localized("settings.batteryPercentPlaceholder", fallback: "10"),
          text: Binding(
            get: { viewModel.batteryInput },
            set: { viewModel.setBatteryInput($0) }
          )
        )
        .frame(width: 52)
        .multilineTextAlignment(.trailing)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          viewModel.commitBatteryInput()
        }
        Text("%")
        Stepper(
          "",
          value: Binding(
            get: { viewModel.batteryCutoffPercent },
            set: { viewModel.setBatteryCutoffPercent($0) }
          ),
          in: 0...100,
          step: 1
        )
        .labelsHidden()
      }
      .disabled(viewModel.isSessionActive)

      if viewModel.batteryCutoffPercent == 0 {
        Text(Self.localized("settings.battery.disabled", fallback: "Automatic stop is off."))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let validationError = viewModel.batteryValidationError {
        Text(validationError)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityLabel(validationError)
      }

      Text(
        Self.localized(
          "settings.battery.help",
          fallback: "Battery protection does not apply while the power adapter is connected. Set 0% to turn it off."
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var shortcutSection: some View {
    Section(
      header: Text(Self.localized("settings.section.shortcut", fallback: "Shortcut & Launch"))
    ) {
      HStack {
        Text(Self.localized("settings.shortcut", fallback: "Global shortcut"))
        Spacer()
        ShortcutRecorderView(
          shortcut: viewModel.shortcut,
          onRecord: viewModel.setShortcut,
          isEnabled: !viewModel.isSessionActive
        )
      }
      .disabled(viewModel.isSessionActive)

      Button(Self.localized("settings.resetDefault", fallback: "Reset to Default")) {
        viewModel.resetToDefault()
      }
      .disabled(viewModel.isSessionActive)

      Toggle(
        Self.localized("settings.launchAtLogin", fallback: "Launch at Login"),
        isOn: Binding(
          get: { viewModel.loginItemStatus == .enabled },
          set: { viewModel.setLaunchAtLogin($0) }
        )
      )

      if viewModel.isSessionActive {
        Text(
          Self.localized(
            "settings.sessionActiveNotice",
            fallback: "End the current session before changing mode, duration, battery, or shortcut settings."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if viewModel.loginItemStatus == .requiresApproval {
        Text(
          Self.localized(
            "settings.loginApprovalRequired",
            fallback: "Approval is required in Login Items."
          )
        )
        .font(.caption)

        Button(
          Self.localized(
            "settings.openLoginItemsSettings",
            fallback: "Open Login Items Settings"
          )
        ) {
          viewModel.openLoginItemSettings()
        }
      }
    }
  }

  private func durationKey(_ duration: SessionDuration) -> String {
    switch duration {
    case .minutes(let minutes):
      return "minutes-\(minutes)"
    case .indefinite:
      return "indefinite"
    }
  }

  private func duration(forKey key: String) -> SessionDuration? {
    switch key {
    case "minutes-30": return .minutes(30)
    case "minutes-60": return .minutes(60)
    case "minutes-120": return .minutes(120)
    case "minutes-240": return .minutes(240)
    case "indefinite": return .indefinite
    default: return nil
    }
  }

  private func durationLabel(_ duration: SessionDuration) -> String {
    switch duration {
    case .minutes(30):
      return Self.localized("duration.30Minutes", fallback: "30 minutes")
    case .minutes(60):
      return Self.localized("duration.1Hour", fallback: "1 hour")
    case .minutes(120):
      return Self.localized("duration.2Hours", fallback: "2 hours")
    case .minutes(240):
      return Self.localized("duration.4Hours", fallback: "4 hours")
    case .minutes(let minutes):
      return String(
        format: Self.localized("duration.minutes", fallback: "%d minutes"),
        minutes
      )
    case .indefinite:
      return Self.localized("duration.untilStopped", fallback: "Until I stop it")
    }
  }

  private static func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
  }
}

private extension SessionDuration {
  var selfKey: String {
    switch self {
    case .minutes(let minutes): return "minutes-\(minutes)"
    case .indefinite: return "indefinite"
    }
  }
}
