import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
  let shortcut: KeyboardShortcut?
  let onRecord: (KeyboardShortcut) -> Void

  var body: some View {
    Text(shortcut.map(Self.displayName) ?? NSLocalizedString("shortcut.record.none", comment: ""))
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityLabel(NSLocalizedString("shortcut.record.accessibilityLabel", comment: ""))
  }

  private static func displayName(_ shortcut: KeyboardShortcut) -> String {
    var result = ""
    if shortcut.modifiers.contains(.control) { result += "⌃" }
    if shortcut.modifiers.contains(.option) { result += "⌥" }
    if shortcut.modifiers.contains(.shift) { result += "⇧" }
    if shortcut.modifiers.contains(.command) { result += "⌘" }
    result += keyName(for: shortcut.keyCode)
    return result
  }

  private static func keyName(for keyCode: UInt32) -> String {
    switch keyCode {
    case 0: return "A"
    case 1: return "S"
    case 2: return "D"
    case 3: return "F"
    case 4: return "H"
    case 5: return "G"
    case 6: return "Z"
    case 7: return "X"
    case 8: return "C"
    case 9: return "V"
    case 11: return "B"
    default: return "\(keyCode)"
    }
  }
}
