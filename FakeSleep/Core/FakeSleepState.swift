import Foundation

enum FakeSleepState: Equatable {
  case awake
  case fakeSleeping
}

enum FakeSleepError: Equatable, LocalizedError {
  case noRestorePath
  case noScreens
  case incompleteOverlayCoverage
  case emergencyEscapeUnavailable

  var localizationKey: String {
    switch self {
    case .noRestorePath:
      "fakeSleep.error.noRestorePath"
    case .noScreens:
      "fakeSleep.error.noScreens"
    case .incompleteOverlayCoverage:
      "fakeSleep.error.incompleteOverlayCoverage"
    case .emergencyEscapeUnavailable:
      "fakeSleep.error.emergencyEscapeUnavailable"
    }
  }

  var errorDescription: String? {
    NSLocalizedString(localizationKey, comment: "")
  }
}

struct ShortcutModifiers: OptionSet, Codable, Hashable {
  let rawValue: UInt32

  static let command = ShortcutModifiers(rawValue: 1 << 0)
  static let option = ShortcutModifiers(rawValue: 1 << 1)
  static let control = ShortcutModifiers(rawValue: 1 << 2)
  static let shift = ShortcutModifiers(rawValue: 1 << 3)
}

struct KeyboardShortcut: Equatable, Codable, Hashable {
  let keyCode: UInt32
  let modifiers: ShortcutModifiers
}

@MainActor
protocol HotKeyRegistering: AnyObject {
  var isPrimaryRegistered: Bool { get }
  func registerPrimary(_ shortcut: KeyboardShortcut, handler: @escaping () -> Void) throws
  func registerEmergencyEscape(handler: @escaping () -> Void) throws
  func unregisterEmergencyEscape()
}
