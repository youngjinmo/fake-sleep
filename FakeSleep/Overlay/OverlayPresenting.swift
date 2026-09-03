@MainActor
protocol OverlayPresenting: AnyObject {
  var coveredScreenIDs: Set<UInt32> { get }
  func reconcile(with screens: [ScreenDescriptor])
  func removeAll()
}
