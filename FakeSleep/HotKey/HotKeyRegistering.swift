@MainActor
protocol HotKeyRegistering: AnyObject {
  var isPrimaryRegistered: Bool { get }
  func registerPrimary(_ shortcut: KeyboardShortcut, handler: @escaping () -> Void) throws
  func unregisterPrimary()
  func registerEmergencyEscape(handler: @escaping () -> Void) throws
  func unregisterEmergencyEscape()
}

@MainActor
extension HotKeyRegistering {
  func unregisterPrimary() {}
}
