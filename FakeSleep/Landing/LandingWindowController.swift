import AppKit
import SwiftUI

@MainActor
final class LandingWindowController: NSWindowController, NSWindowDelegate {
  let viewModel: LandingViewModel

  private let coordinator: FakeSleepCoordinator
  private var stateObserverID: UUID?
  private var isPreparedForTermination = false

  init(viewModel: LandingViewModel, coordinator: FakeSleepCoordinator) {
    self.viewModel = viewModel
    self.coordinator = coordinator
    super.init(window: nil)

    stateObserverID = coordinator.addStateObserver { [weak self] state in
      guard state == .fakeSleeping else { return }
      self?.close()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func open() {
    guard !isPreparedForTermination else { return }

    if window == nil {
      window = makeWindow()
    }

    guard let window else { return }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeKey()
    window.makeMain()
  }

  @discardableResult
  func openAtLaunchIfNeeded() -> Bool {
    guard !isPreparedForTermination, viewModel.showsAtLaunch else { return false }

    open()
    return window != nil
  }

  override func close() {
    guard let window else { return }

    window.delegate = nil
    window.close()
    self.window = nil
  }

  func prepareForTermination() {
    guard !isPreparedForTermination else { return }

    isPreparedForTermination = true
    removeStateObserver()
    viewModel.prepareForTermination()
    close()
  }

  func windowWillClose(_ notification: Notification) {
    guard let closingWindow = notification.object as? NSWindow,
          let currentWindow = window,
          closingWindow === currentWindow else {
      return
    }

    window = nil
  }

  deinit {
    let coordinator = coordinator
    let stateObserverID = stateObserverID

    if let stateObserverID {
      Task { @MainActor in
        coordinator.removeStateObserver(stateObserverID)
      }
    }
  }

  private func makeWindow() -> NSWindow {
    let contentView = NSHostingView(rootView: LandingView(viewModel: viewModel))
    let landingWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    landingWindow.title = NSLocalizedString(
      "landing.title",
      bundle: .main,
      value: "Fake Sleep",
      comment: ""
    )
    landingWindow.isReleasedWhenClosed = false
    landingWindow.contentView = contentView
    landingWindow.delegate = self
    landingWindow.center()
    return landingWindow
  }

  private func removeStateObserver() {
    guard let stateObserverID else { return }

    coordinator.removeStateObserver(stateObserverID)
    self.stateObserverID = nil
  }
}
