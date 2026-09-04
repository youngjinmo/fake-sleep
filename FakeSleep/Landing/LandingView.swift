import SwiftUI

enum LandingWindowLayout {
  static let width: CGFloat = 560
  static let height: CGFloat = 600
  static let footerMinHeight: CGFloat = 72
}

struct LandingView: View {
  @ObservedObject var viewModel: LandingViewModel

  var body: some View {
    VStack(spacing: 0) {
      ScrollView(.vertical) {
        stepContent
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(28)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .layoutPriority(1)

      Divider()

      footer
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(
          maxWidth: .infinity,
          minHeight: LandingWindowLayout.footerMinHeight,
          alignment: .center
        )
    }
    .frame(width: LandingWindowLayout.width, height: LandingWindowLayout.height)
    .onAppear {
      viewModel.beginOnboarding()
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch viewModel.currentStep {
    case 1:
      valueStep
    case 2:
      modeStep
    default:
      settingsStep
    }
  }

  private var valueStep: some View {
    VStack(alignment: .leading, spacing: 22) {
      titleBlock(
        title: Self.localized(
          "onboarding.value.title",
          fallback: "Mac keeps working while your screen stays safe"
        ),
        description: Self.localized(
          "onboarding.value.description",
          fallback: "Step away without interrupting downloads, builds, or AI work."
        )
      )

      VStack(alignment: .leading, spacing: 16) {
        valueRow(
          icon: "bolt.fill",
          title: Self.localized(
            "onboarding.value.keepAwake.title",
            fallback: "Keep Mac awake"
          ),
          description: Self.localized(
            "onboarding.value.keepAwake.description",
            fallback: "Prevents idle system sleep while your session is running."
          )
        )
        valueRow(
          icon: "lock.fill",
          title: Self.localized(
            "onboarding.value.macOSLock.title",
            fallback: "Use macOS Lock"
          ),
          description: Self.localized(
            "onboarding.value.macOSLock.description",
            fallback: "Use Control-Command-Q to lock macOS before you leave."
          )
        )
        valueRow(
          icon: "battery.100percent",
          title: Self.localized(
            "onboarding.value.battery.title",
            fallback: "Protect your battery"
          ),
          description: Self.localized(
            "onboarding.value.battery.description",
            fallback: "End the session automatically at the battery level you choose."
          )
        )
      }

      Text(
        Self.localized(
          "onboarding.value.limitation",
          fallback: "Fake Sleep cannot prevent a closed lid, forced sleep, or thermal protection."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .accessibilityAddTraits(.isStaticText)
    }
  }

  private var modeStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      titleBlock(
        title: Self.localized(
          "onboarding.mode.title",
          fallback: "Choose how to leave your Mac"
        ),
        description: Self.localized(
          "onboarding.mode.description",
          fallback: "The recommended mode keeps the Mac running and relies on macOS for account security."
        )
      )

      modeCard(
        mode: .secureLeave,
        icon: "lock.shield.fill",
        title: Self.localized(
          "mode.secureLeave.title",
          fallback: "Leave safely"
        ),
        description: Self.localized(
          "mode.secureLeave.description",
          fallback: "Prevent idle system sleep and lock macOS with the macOS lock shortcut."
        ),
        details: [
          Self.localized(
            "mode.secureLeave.lock",
            fallback: "Use the macOS lock shortcut to lock macOS."
          ),
          Self.localized(
            "mode.secureLeave.displaySleep",
            fallback: "Display sleep follows your macOS settings."
          )
        ],
        badge: Self.localized("mode.recommended", fallback: "Recommended")
      )

      modeCard(
        mode: .blackout,
        icon: "rectangle.on.rectangle.slash",
        title: Self.localized(
          "mode.blackout.title",
          fallback: "Hide the screen only"
        ),
        description: Self.localized(
          "mode.blackout.description",
          fallback: "Cover displays with a black overlay while the Mac keeps running."
        ),
        details: [
          Self.localized(
            "mode.blackout.displaySleep",
            fallback: "Display sleep follows your macOS settings."
          )
        ],
        badge: nil,
        warning: Self.localized(
          "mode.blackout.warning",
          fallback: "Mac is not locked. This mode is not a security feature."
        )
      )
    }
  }

  private var settingsStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      titleBlock(
        title: Self.localized(
          "onboarding.settings.title",
          fallback: "Set your defaults"
        ),
        description: Self.localized(
          "onboarding.settings.description",
          fallback: "You can change these choices later in Settings."
        )
      )

      VStack(alignment: .leading, spacing: 12) {
        Text(Self.localized("onboarding.shortcut.title", fallback: "Global shortcut"))
          .font(.headline)
        ShortcutRecorderView(
          shortcut: viewModel.selectedShortcut,
          onRecord: viewModel.setDraftShortcut
        )
        .accessibilityElement(children: .contain)
      }

      Picker(
        Self.localized("onboarding.duration.title", fallback: "Default session time"),
        selection: durationSelection
      ) {
        ForEach(Array(SessionDuration.presets.enumerated()), id: \.offset) { index, duration in
          Text(Self.durationLabel(duration))
            .tag(index)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(Self.localized("onboarding.battery.title", fallback: "Battery auto-stop"))
          Spacer()
          TextField(
            Self.localized("onboarding.battery.inputPlaceholder", fallback: "Percent"),
            text: batteryInput
          )
          .multilineTextAlignment(.trailing)
          .frame(width: 56)
          .textFieldStyle(.roundedBorder)
          Text("%")
        }

        Stepper(
          Self.localized(
            "onboarding.battery.stepper",
            fallback: "Stop at %@ battery",
            argument: "\(viewModel.selectedBatteryCutoffPercent)"
          ),
          value: batterySelection,
          in: 0...100,
          step: 1
        )

        Text(
          viewModel.selectedBatteryCutoffPercent == 0
            ? Self.localized(
              "onboarding.battery.disabled",
              fallback: "Automatic battery stop is off."
            )
            : Self.localized(
              "onboarding.battery.description",
              fallback: "On battery power, end the session at or below this level."
            )
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if let onboardingError = viewModel.onboardingError {
          Text(onboardingError)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Toggle(
        Self.localized("onboarding.loginAtLaunch.title", fallback: "Launch at login"),
        isOn: launchAtLogin
      )

      Text(summary)
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityLabel(
          Self.localized(
            "onboarding.summary.accessibilityLabel",
            fallback: "Selected defaults"
          )
        )
    }
  }

  private var footer: some View {
    HStack {
      Button(Self.localized("onboarding.previous", fallback: "Previous")) {
        viewModel.previous()
      }
      .disabled(!viewModel.canGoBack)

      Spacer()

      Text(
        Self.localized(
          "onboarding.progress",
          fallback: "%d/3",
          integerArgument: viewModel.currentStep
        )
      )
      .accessibilityLabel(
        Self.localized(
          "onboarding.progress.accessibilityLabel",
          fallback: "Step %@ of 3",
          argument: "\(viewModel.currentStep)"
        )
      )

      Spacer()

      if viewModel.isLastStep {
        Button(Self.localized("onboarding.complete", fallback: "Finish Setup")) {
          viewModel.completeOnboarding()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
      } else {
        Button(Self.localized("onboarding.next", fallback: "Next")) {
          viewModel.next()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
      }
    }
  }

  private func titleBlock(title: String, description: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.title2)
        .fontWeight(.semibold)
        .fixedSize(horizontal: false, vertical: true)
      Text(description)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func valueRow(icon: String, title: String, description: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .frame(width: 24)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        Text(description)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func modeCard(
    mode: FakeSleepMode,
    icon: String,
    title: String,
    description: String,
    details: [String],
    badge: String?,
    warning: String? = nil
  ) -> some View {
    Button {
      viewModel.setMode(mode)
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
          .frame(width: 24)
          .foregroundStyle(.tint)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 8) {
            Text(title)
              .font(.headline)
            if let badge {
              Text(badge)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.tint.opacity(0.15), in: Capsule())
            }
            Spacer(minLength: 0)
            Image(systemName: viewModel.selectedMode == mode ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(.tint)
              .accessibilityHidden(true)
          }

          Text(description)
            .fixedSize(horizontal: false, vertical: true)

          ForEach(details, id: \.self) { detail in
            Text(detail)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          if let warning {
            Text(warning)
              .font(.caption)
              .foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        viewModel.selectedMode == mode
          ? Color.accentColor.opacity(0.10)
          : Color.secondary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 10)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .stroke(
            viewModel.selectedMode == mode ? Color.accentColor : Color.clear,
            lineWidth: 1
          )
      }
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(viewModel.selectedMode == mode ? .isSelected : [])
    .accessibilityValue(
      viewModel.selectedMode == mode
        ? Self.localized("onboarding.mode.selected", fallback: "Selected")
        : Self.localized("onboarding.mode.notSelected", fallback: "Not selected")
    )
  }

  private var durationSelection: Binding<Int> {
    Binding(
      get: {
        SessionDuration.presets.firstIndex(of: viewModel.selectedDuration) ?? 0
      },
      set: { index in
        guard SessionDuration.presets.indices.contains(index) else { return }
        viewModel.setDuration(SessionDuration.presets[index])
      }
    )
  }

  private var batterySelection: Binding<Int> {
    Binding(
      get: { viewModel.selectedBatteryCutoffPercent },
      set: { viewModel.setBatteryCutoffPercent($0) }
    )
  }

  private var batteryInput: Binding<String> {
    Binding(
      get: { viewModel.batteryInput },
      set: { viewModel.setBatteryInput($0) }
    )
  }

  private var launchAtLogin: Binding<Bool> {
    Binding(
      get: { viewModel.selectedLaunchAtLogin },
      set: { viewModel.setLaunchAtLogin($0) }
    )
  }

  private var summary: String {
    Self.localized(
      "onboarding.summary",
      fallback: "%@ · %@ · Battery %@",
      arguments: [
        Self.modeLabel(viewModel.selectedMode),
        Self.durationLabel(viewModel.selectedDuration),
        "\(viewModel.selectedBatteryCutoffPercent)%"
      ]
    )
  }

  private static func modeLabel(_ mode: FakeSleepMode) -> String {
    switch mode {
    case .secureLeave:
      return localized("mode.secureLeave.title", fallback: "Leave safely")
    case .blackout:
      return localized("mode.blackout.title", fallback: "Hide the screen only")
    }
  }

  private static func durationLabel(_ duration: SessionDuration) -> String {
    switch duration {
    case .minutes(30):
      return localized("duration.30Minutes", fallback: "30 minutes")
    case .minutes(60):
      return localized("duration.1Hour", fallback: "1 hour")
    case .minutes(120):
      return localized("duration.2Hours", fallback: "2 hours")
    case .minutes(240):
      return localized("duration.4Hours", fallback: "4 hours")
    case .minutes:
      return localized("duration.custom", fallback: "Limited time")
    case .indefinite:
      return localized("duration.indefinite", fallback: "Until I stop it")
    }
  }

  private static func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
  }

  private static func localized(
    _ key: String,
    fallback: String,
    argument: String
  ) -> String {
    String(format: localized(key, fallback: fallback), argument)
  }

  private static func localized(
    _ key: String,
    fallback: String,
    integerArgument: Int
  ) -> String {
    String(format: localized(key, fallback: fallback), integerArgument)
  }

  private static func localized(
    _ key: String,
    fallback: String,
    arguments: [String]
  ) -> String {
    String(format: localized(key, fallback: fallback), arguments: arguments)
  }
}
