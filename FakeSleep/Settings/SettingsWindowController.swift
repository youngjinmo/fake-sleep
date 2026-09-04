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
      let contentSize = NSSize(
        width: SettingsWindowLayout.width,
        height: SettingsWindowLayout.minHeight
      )
      let settingsWindow = NSWindow(
        contentRect: NSRect(origin: .zero, size: contentSize),
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
      settingsWindow.contentMinSize = contentSize
      settingsWindow.contentView = contentView
      contentView.layoutSubtreeIfNeeded()
      let fittingHeight = max(contentSize.height, contentView.fittingSize.height)
      settingsWindow.setContentSize(
        NSSize(width: contentSize.width, height: fittingHeight)
      )
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
