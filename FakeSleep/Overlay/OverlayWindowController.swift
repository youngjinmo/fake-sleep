import AppKit

@MainActor
protocol OverlayWindowing: AnyObject {
  var frame: CGRect { get set }
  func orderFrontRegardless()
  func close()
}

@MainActor
protocol OverlayWindowCreating: AnyObject {
  func makeWindow(frame: CGRect) -> OverlayWindowing?
}

@MainActor
final class OverlayWindow: NSWindow, OverlayWindowing {
  override var frame: CGRect {
    get { super.frame }
    set { setFrame(newValue, display: true) }
  }
}

@MainActor
final class OverlayWindowFactory: OverlayWindowCreating {
  func makeWindow(frame: CGRect) -> OverlayWindowing? {
    let window = OverlayWindow(
      contentRect: frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )

    window.backgroundColor = .black
    window.isOpaque = true
    window.alphaValue = 1
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.isReleasedWhenClosed = false
    window.level = .screenSaver
    window.collectionBehavior = [
      .canJoinAllSpaces,
      .stationary,
      .fullScreenAuxiliary,
      .ignoresCycle,
    ]
    window.animationBehavior = .none
    window.setFrame(frame, display: false)
    window.orderFrontRegardless()

    return window
  }
}

typealias SystemOverlayWindowFactory = OverlayWindowFactory

@MainActor
final class OverlayWindowController: OverlayPresenting {
  private let factory: OverlayWindowCreating
  private var windows: [UInt32: OverlayWindowing] = [:]
  private var notificationObservers: OverlayNotificationObserverStore?

  var onScreenConfigurationChange: (() -> Void)?
  var onWake: (() -> Void)?

  var coveredScreenIDs: Set<UInt32> {
    Set(windows.keys)
  }

  init(
    factory: OverlayWindowCreating,
    notificationCenter: NotificationCenter,
    workspaceNotificationCenter: NotificationCenter
  ) {
    self.factory = factory
    self.notificationObservers = nil
    observeNotifications(
      notificationCenter: notificationCenter,
      workspaceNotificationCenter: workspaceNotificationCenter
    )
  }

  convenience init() {
    self.init(
      factory: OverlayWindowFactory(),
      notificationCenter: .default,
      workspaceNotificationCenter: NSWorkspace.shared.notificationCenter
    )
  }

  func reconcile(with screens: [ScreenDescriptor]) {
    let uniqueScreens = uniqueScreens(from: screens)
    let connectedScreenIDs = Set(uniqueScreens.map(\.id))

    removeDisconnectedScreens(connectedScreenIDs)

    for screen in uniqueScreens {
      if let window = windows[screen.id] {
        window.frame = screen.frame
        window.orderFrontRegardless()
      } else if let window = factory.makeWindow(frame: screen.frame) {
        windows[screen.id] = window
        window.orderFrontRegardless()
      }
    }
  }

  func removeAll() {
    for window in windows.values {
      window.close()
    }
    windows.removeAll()
  }

  private func observeNotifications(
    notificationCenter: NotificationCenter,
    workspaceNotificationCenter: NotificationCenter
  ) {
    notificationObservers = OverlayNotificationObserverStore(
      notificationCenter: notificationCenter,
      workspaceNotificationCenter: workspaceNotificationCenter,
      onScreenConfigurationChange: { [weak self] in
        self?.onScreenConfigurationChange?()
      },
      onWake: { [weak self] in
        self?.onWake?()
      }
    )
  }

  private func uniqueScreens(from screens: [ScreenDescriptor]) -> [ScreenDescriptor] {
    var seenIDs = Set<UInt32>()
    return screens.filter { seenIDs.insert($0.id).inserted }
  }

  private func removeDisconnectedScreens(_ connectedScreenIDs: Set<UInt32>) {
    let disconnectedScreenIDs = Set(windows.keys).subtracting(connectedScreenIDs)
    for screenID in disconnectedScreenIDs {
      guard let window = windows.removeValue(forKey: screenID) else { continue }
      window.close()
    }
  }
}

private final class OverlayNotificationObserverStore {
  private let notificationCenter: NotificationCenter
  private let workspaceNotificationCenter: NotificationCenter
  private var screenConfigurationObserver: NSObjectProtocol?
  private var wakeObserver: NSObjectProtocol?

  init(
    notificationCenter: NotificationCenter,
    workspaceNotificationCenter: NotificationCenter,
    onScreenConfigurationChange: @escaping @MainActor () -> Void,
    onWake: @escaping @MainActor () -> Void
  ) {
    self.notificationCenter = notificationCenter
    self.workspaceNotificationCenter = workspaceNotificationCenter
    screenConfigurationObserver = notificationCenter.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        onScreenConfigurationChange()
      }
    }
    wakeObserver = workspaceNotificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        onWake()
      }
    }
  }

  deinit {
    if let screenConfigurationObserver {
      notificationCenter.removeObserver(screenConfigurationObserver)
    }
    if let wakeObserver {
      workspaceNotificationCenter.removeObserver(wakeObserver)
    }
  }
}
