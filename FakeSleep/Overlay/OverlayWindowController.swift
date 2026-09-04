import AppKit

@MainActor
protocol OverlayWindowing: AnyObject {
  var frame: CGRect { get set }
  var onRestoreRequested: (() -> Void)? { get set }
  func orderFrontRegardless()
  func close()

  // Optional hooks let the real AppKit window receive and consume the first
  // restore input without requiring every test double to model NSWindow.
  func setRestoreHandler(_ handler: (() -> Void)?)
  func setRestoreHintVisible(_ visible: Bool, animated: Bool)
  func makeKeyAndOrderFront()
  func resignKeyOverlay()
  func setCanBecomeKey(_ canBecomeKey: Bool)
}

@MainActor
extension OverlayWindowing {
  var onRestoreRequested: (() -> Void)? {
    get { nil }
    set {}
  }

  func setRestoreHandler(_ handler: (() -> Void)?) {
    onRestoreRequested = handler
  }

  func setRestoreHintVisible(_ visible: Bool, animated: Bool) {}

  func makeKeyAndOrderFront() {
    orderFrontRegardless()
  }

  func resignKeyOverlay() {}

  func setCanBecomeKey(_ canBecomeKey: Bool) {}
}

@MainActor
protocol OverlayWindowCreating: AnyObject {
  func makeWindow(frame: CGRect) -> OverlayWindowing?
}

@MainActor
final class OverlayWindow: NSWindow, OverlayWindowing {
  private var didRequestRestore = false
  private var allowsKeyWindow = true
  private var restoreHintView: OverlayRestoreHintView?

  var onRestoreRequested: (() -> Void)?

  override var frame: CGRect {
    get { super.frame }
    set { setFrame(newValue, display: true) }
  }

  override var canBecomeKey: Bool { allowsKeyWindow }
  override var canBecomeMain: Bool { true }

  func setRestoreHandler(_ handler: (() -> Void)?) {
    onRestoreRequested = handler
  }

  func setRestoreHintVisible(_ visible: Bool, animated: Bool) {
    guard let contentView else { return }

    if visible {
      let hint = restoreHintView ?? makeRestoreHintView(in: contentView)
      restoreHintView = hint
      hint.alphaValue = animated ? 0 : 1
      if animated {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.2
          hint.animator().alphaValue = 1
        }
      }
      return
    }

    guard let hint = restoreHintView else { return }
    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        hint.animator().alphaValue = 0
      }
    } else {
      hint.alphaValue = 0
    }
  }

  func makeKeyAndOrderFront() {
    makeKeyAndOrderFront(nil)
  }

  func resignKeyOverlay() {
    resignKey()
  }

  func setCanBecomeKey(_ canBecomeKey: Bool) {
    allowsKeyWindow = canBecomeKey
  }

  override func sendEvent(_ event: NSEvent) {
    if shouldRequestRestore(for: event) {
      requestRestore()
      return
    }

    super.sendEvent(event)
  }

  private func shouldRequestRestore(for event: NSEvent) -> Bool {
    switch event.type {
    case .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown:
      return true
    default:
      return false
    }
  }

  private func requestRestore() {
    guard !didRequestRestore else { return }

    didRequestRestore = true
    onRestoreRequested?()
  }

  private func makeRestoreHintView(in contentView: NSView) -> OverlayRestoreHintView {
    let hint = OverlayRestoreHintView(frame: contentView.bounds)
    hint.autoresizingMask = [.width, .height]
    contentView.addSubview(hint)
    return hint
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
    window.ignoresMouseEvents = false
    window.acceptsMouseMovedEvents = true
    window.isReleasedWhenClosed = false
    window.contentView = NSView(
      frame: NSRect(origin: .zero, size: frame.size)
    )
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
  private var primaryScreenID: UInt32?
  private var restoreRequestInFlight = false

  var onRestoreRequested: (() -> Void)? {
    didSet {
      installRestoreHandlers()
    }
  }

  var onScreenConfigurationChange: (() -> Void)?
  var onWake: (() -> Void)?

  var coveredScreenIDs: Set<UInt32> {
    Set(windows.keys)
  }

  var keyScreenID: UInt32? {
    primaryScreenID
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
        installRestoreHandler(on: window)
        window.orderFrontRegardless()
      } else if let window = factory.makeWindow(frame: screen.frame) {
        windows[screen.id] = window
        installRestoreHandler(on: window)
        window.orderFrontRegardless()
      }
    }

    primaryScreenID = uniqueScreens.first(where: { windows[$0.id] != nil })?.id
    enforcePrimaryKeyWindow()
  }

  func removeAll() {
    for window in windows.values {
      window.setRestoreHandler(nil)
      window.close()
    }
    windows.removeAll()
    primaryScreenID = nil
    restoreRequestInFlight = false
  }

  func setRestoreHandler(_ handler: (() -> Void)?) {
    onRestoreRequested = handler
  }

  func setRestoreHintVisible(_ visible: Bool, animated: Bool) {
    for window in windows.values {
      window.setRestoreHintVisible(visible, animated: animated)
    }
  }

  func requestRestore() {
    handleRestoreRequest()
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
      window.setRestoreHandler(nil)
      window.close()
    }
  }

  private func installRestoreHandlers() {
    for window in windows.values {
      installRestoreHandler(on: window)
    }
  }

  private func installRestoreHandler(on window: OverlayWindowing) {
    window.setRestoreHandler { [weak self] in
      self?.handleRestoreRequest()
    }
  }

  private func handleRestoreRequest() {
    guard !restoreRequestInFlight else { return }

    restoreRequestInFlight = true
    if let onRestoreRequested {
      onRestoreRequested()
    } else {
      removeAll()
    }
  }

  private func enforcePrimaryKeyWindow() {
    guard let primaryScreenID,
          let primaryWindow = windows[primaryScreenID] else {
      return
    }

    for (screenID, window) in windows where screenID != primaryScreenID {
      window.setCanBecomeKey(false)
      window.resignKeyOverlay()
      window.orderFrontRegardless()
    }

    primaryWindow.setCanBecomeKey(true)
    primaryWindow.makeKeyAndOrderFront()
  }
}

private final class OverlayRestoreHintView: NSView {
  private let stackView = NSStackView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func configure() {
    let title = NSTextField(labelWithString: Self.localized(
      "overlay.restoreHint.title",
      fallback: "The screen is covered"
    ))
    title.font = .systemFont(ofSize: 24, weight: .semibold)
    title.textColor = .white
    title.alignment = .center

    let message = NSTextField(labelWithString: Self.localized(
      "overlay.restoreHint.message",
      fallback: "Click or press any key to return."
    ))
    message.font = .systemFont(ofSize: 15)
    message.textColor = NSColor.white.withAlphaComponent(0.85)
    message.alignment = .center

    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.spacing = 8
    stackView.addArrangedSubview(title)
    stackView.addArrangedSubview(message)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stackView)

    NSLayoutConstraint.activate([
      stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
      stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
      stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
      stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  private static func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
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
