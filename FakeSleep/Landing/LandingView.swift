import Foundation
import SwiftUI

struct LandingView: View {
  @ObservedObject var viewModel: LandingViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text(Self.localized("landing.title", fallback: "Fake Sleep"))
            .font(.largeTitle)
            .fontWeight(.semibold)

          Text(
            Self.localized(
              "landing.description",
              fallback: "A visual blackout for every connected display."
            )
          )
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 10) {
          Text(Self.localized("landing.instructions", fallback: "How to use"))
            .font(.headline)

          if let shortcut = viewModel.shortcut {
            Text(
              Self.localized(
                "landing.shortcutInstruction",
                fallback: "Press %@ anywhere, or use the button below.",
                argument: KeyboardShortcutFormatter.string(for: shortcut)
              )
            )
          } else {
            Text(
              Self.localized(
                "landing.shortcutNotSet",
                fallback: "Shortcut not set. Open Settings… to choose one, or use the button below."
              )
            )
          }

          Text(
            Self.localized(
              "landing.restoreInstruction",
              fallback: "Press Esc at any time while Fake Sleep is active to restore your displays."
            )
          )
        }

        Text(
          Self.localized(
            "landing.displayLimitation",
            fallback: "Fake Sleep covers your displays with black overlays. It does not change display brightness or power."
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        if let error = viewModel.error {
          Text(Self.localizedError(error))
            .foregroundStyle(.red)
            .font(.callout)
        }

        HStack(spacing: 12) {
          Button(Self.localized("landing.darkenScreens", fallback: "Darken Screens")) {
            viewModel.activate()
          }
          .buttonStyle(.borderedProminent)
          .disabled(viewModel.isFakeSleeping)

          Button(Self.localized("landing.openSettings", fallback: "Open Settings…")) {
            viewModel.openSettings()
          }
          .buttonStyle(.bordered)
        }

        Toggle(
          Self.localized(
            "landing.dontShowAtLaunch",
            fallback: "Don't show this guide at launch"
          ),
          isOn: Binding(
            get: { !viewModel.showsAtLaunch },
            set: { viewModel.setShowsAtLaunch(!$0) }
          )
        )
      }
      .padding(32)
    }
    .frame(width: 520, height: 500)
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

  private static func localizedError(_ error: FakeSleepError) -> String {
    let fallback: String
    switch error {
    case .noRestorePath:
      fallback = "No restore shortcut is available."
    case .noScreens:
      fallback = "No displays are available."
    case .incompleteOverlayCoverage:
      fallback = "Could not cover every display."
    case .emergencyEscapeUnavailable:
      fallback = "Emergency Escape could not be registered."
    }
    return localized(error.localizationKey, fallback: fallback)
  }
}
