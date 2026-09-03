import AppKit

@MainActor
final class StatusMenuController: NSObject {
  let statusItem: NSStatusItem
  private(set) var statusImageName = "moon"

  private let statusBar: NSStatusBar
  private weak var coordinator: FakeSleepCoordinator?
  private let settingsHandler: () -> Void
  private let quitHandler: () -> Void
  private var stateObserverID: UUID?
  private var isClosed = false

  init(
    coordinator: FakeSleepCoordinator,
    settingsHandler: @escaping () -> Void = {},
    quitHandler: @escaping () -> Void = { NSApp.terminate(nil) },
    statusBar: NSStatusBar = .system
  ) {
    self.coordinator = coordinator
    self.settingsHandler = settingsHandler
    self.quitHandler = quitHandler
    self.statusBar = statusBar
    self.statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(
      NSMenuItem(
        title: Self.localized("menu.startFakeSleep", fallback: "Start Fake Sleep"),
        action: #selector(toggleFakeSleep),
        keyEquivalent: ""
      )
    )
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: Self.localized("menu.settings", fallback: "Settings…"),
        action: #selector(openSettings),
        keyEquivalent: ""
      )
    )
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: Self.localized("menu.quitFakeSleep", fallback: "Quit Fake Sleep"),
        action: #selector(quit),
        keyEquivalent: ""
      )
    )
    menu.items.forEach { $0.target = self }
    statusItem.menu = menu

    if let button = statusItem.button {
      button.imagePosition = .imageOnly
      button.setAccessibilityLabel(
        Self.localized("menu.accessibilityLabel", fallback: "Fake Sleep")
      )
      button.toolTip = Self.localized("menu.tooltip", fallback: "Fake Sleep")
    }

    stateObserverID = coordinator.addStateObserver { [weak self] _ in
      self?.refresh()
    }
    refresh()
  }

  func close() {
    guard !isClosed else { return }
    isClosed = true

    if let stateObserverID {
      coordinator?.removeStateObserver(stateObserverID)
      self.stateObserverID = nil
    }
    statusItem.menu = nil
    statusItem.button?.image = nil
    statusBar.removeStatusItem(statusItem)
  }

  func refresh() {
    guard !isClosed, let coordinator else { return }
    let isSleeping = coordinator.state == .fakeSleeping
    statusImageName = isSleeping ? "moon.fill" : "moon"
    statusItem.menu?.items.first?.title = isSleeping
      ? Self.localized("menu.restoreDisplays", fallback: "Restore Displays")
      : Self.localized("menu.startFakeSleep", fallback: "Start Fake Sleep")
    let imageName = statusImageName
    let image = NSImage(
      systemSymbolName: imageName,
      accessibilityDescription: nil
    ) ?? NSImage(size: NSSize(width: 18, height: 18))
    image.setName(imageName)
    if let button = statusItem.button {
      button.image = image
      button.image?.setName(imageName)
    }
    statusItem.button?.image?.isTemplate = true
    statusItem.button?.setAccessibilityLabel(
      isSleeping
        ? Self.localized("menu.restoreAccessibilityLabel", fallback: "Restore Displays")
        : Self.localized("menu.accessibilityLabel", fallback: "Fake Sleep")
    )
    statusItem.button?.toolTip = isSleeping
      ? Self.localized("menu.restoreTooltip", fallback: "Restore Displays")
      : Self.localized("menu.tooltip", fallback: "Fake Sleep")
  }

  @objc
  private func toggleFakeSleep() {
    coordinator?.toggle()
  }

  @objc
  private func openSettings() {
    settingsHandler()
  }

  @objc
  private func quit() {
    quitHandler()
  }

  private static func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
  }
}
