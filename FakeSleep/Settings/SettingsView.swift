import SwiftUI

struct SettingsView: View {
  @ObservedObject var viewModel: SettingsViewModel

  var body: some View {
    Form {
      Section {
        HStack {
          Text(Self.localized("settings.shortcut", fallback: "Shortcut"))
          Spacer()
          ShortcutRecorderView(
            shortcut: viewModel.shortcut,
            onRecord: viewModel.setShortcut
          )
        }

        Button(Self.localized("settings.resetDefault", fallback: "Reset to Default")) {
          viewModel.resetToDefault()
        }
      }

      Section {
        Toggle(
          Self.localized("settings.launchAtLogin", fallback: "Launch at Login"),
          isOn: Binding(
            get: { viewModel.loginItemStatus == .enabled },
            set: { viewModel.setLaunchAtLogin($0) }
          )
        )

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

      if let error = viewModel.error {
        Text(error.localizedDescription)
          .foregroundStyle(.red)
          .font(.caption)
      }
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 420)
  }

  private static func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
  }
}
