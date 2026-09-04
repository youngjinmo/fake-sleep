@MainActor
protocol OverlayPresenting: AnyObject {
  var coveredScreenIDs: Set<UInt32> { get }
  var onRestoreRequested: (() -> Void)? { get set }
  func reconcile(with screens: [ScreenDescriptor])
  func removeAll()

  // The default implementation keeps lightweight presenters source-compatible
  // while allowing the application presenter to connect the shared restore
  // path.
  func setRestoreHandler(_ handler: (() -> Void)?)
}

@MainActor
extension OverlayPresenting {
  var onRestoreRequested: (() -> Void)? {
    get { nil }
    set {}
  }

  func setRestoreHandler(_ handler: (() -> Void)?) {
    onRestoreRequested = handler
  }
}
