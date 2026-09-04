import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
  private let viewModel: SettingsViewModel
  private let notificationCenter: NotificationCenter
  private var activeObserver: NSObjectProtocol?

  init(
    viewModel: SettingsViewModel,
    notificationCenter: NotificationCenter = .default
  ) {
    self.viewModel = viewModel
    self.notificationCenter = notificationCenter
    super.init(window: nil)

    activeObserver = notificationCenter.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.viewModel.refreshLoginItemStatus()
      }
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func open() {
    if window == nil {
      let contentView = NSHostingView(rootView: SettingsView(viewModel: viewModel))
      let settingsWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      settingsWindow.title = NSLocalizedString(
        "settings.title",
        bundle: .main,
        value: "Fake Sleep Settings",
        comment: ""
      )
      settingsWindow.isReleasedWhenClosed = false
      settingsWindow.contentView = contentView
      settingsWindow.center()
      window = settingsWindow
    }

    viewModel.refreshLoginItemStatus()
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    window?.makeKey()
    window?.makeMain()
  }

  override func close() {
    if let activeObserver {
      notificationCenter.removeObserver(activeObserver)
      self.activeObserver = nil
    }
    window?.close()
  }
}
