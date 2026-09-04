import Carbon.HIToolbox
import Foundation

struct ShortcutModifiers: OptionSet, Codable, Hashable {
  let rawValue: UInt32

  static let command = ShortcutModifiers(rawValue: 1 << 0)
  static let option = ShortcutModifiers(rawValue: 1 << 1)
  static let control = ShortcutModifiers(rawValue: 1 << 2)
  static let shift = ShortcutModifiers(rawValue: 1 << 3)

  static let persistedMask: ShortcutModifiers = [.command, .option, .control, .shift]
}

struct KeyboardShortcut: Equatable, Codable, Hashable {
  let keyCode: UInt32
  let modifiers: ShortcutModifiers

  static let defaultShortcut = KeyboardShortcut(
    keyCode: UInt32(kVK_ANSI_S),
    modifiers: [.control, .command]
  )

  static let legacyDefaultShortcut = KeyboardShortcut(
    keyCode: UInt32(kVK_ANSI_S),
    modifiers: [.option, .command]
  )
}
