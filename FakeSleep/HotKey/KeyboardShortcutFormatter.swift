enum KeyboardShortcutFormatter {
  static func string(for shortcut: KeyboardShortcut) -> String {
    string(from: shortcut)
  }

  static func string(from shortcut: KeyboardShortcut) -> String {
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
    case 12: return "Q"
    case 13: return "W"
    case 14: return "E"
    case 15: return "R"
    case 16: return "Y"
    case 17: return "T"
    case 18: return "1"
    case 19: return "2"
    case 20: return "3"
    case 21: return "4"
    case 22: return "6"
    case 23: return "5"
    case 24: return "="
    case 25: return "9"
    case 26: return "7"
    case 27: return "-"
    case 28: return "8"
    case 29: return "0"
    case 30: return "]"
    case 31: return "O"
    case 32: return "U"
    case 33: return "["
    case 34: return "I"
    case 35: return "P"
    case 36: return "Return"
    case 37: return "L"
    case 38: return "J"
    case 39: return "'"
    case 40: return "K"
    case 41: return ";"
    case 42: return "\\"
    case 43: return ","
    case 44: return "/"
    case 45: return "N"
    case 46: return "M"
    case 47: return "."
    case 48: return "Tab"
    case 49: return "Space"
    case 50: return "Grave"
    case 51: return "Delete"
    case 53: return "Escape"
    default: return "Key \(keyCode)"
    }
  }
}
