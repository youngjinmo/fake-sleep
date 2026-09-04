import Carbon.HIToolbox
import CoreFoundation
import Foundation

enum ShortcutValidationError: Error, Equatable, LocalizedError {
  case keyRequired
  case modifierRequired
  case primaryModifierRequired
  case unsupportedKey
  case unsupportedModifiers
  case escapeNotAllowed

  var localizationKey: String {
    switch self {
    case .keyRequired:
      "shortcut.error.keyRequired"
    case .modifierRequired:
      "shortcut.error.modifierRequired"
    case .primaryModifierRequired:
      "shortcut.error.primaryModifierRequired"
    case .unsupportedKey:
      "shortcut.error.unsupportedKey"
    case .unsupportedModifiers:
      "shortcut.error.unsupportedModifiers"
    case .escapeNotAllowed:
      "shortcut.error.escapeNotAllowed"
    }
  }

  var errorDescription: String? {
    NSLocalizedString(localizationKey, comment: "")
  }
}

enum ShortcutManagerError: Error, Equatable, LocalizedError {
  case validation(ShortcutValidationError)
  case registrationFailed
  case persistenceFailed
  case defaultUnavailable

  var localizationKey: String {
    switch self {
    case .validation(let error):
      error.localizationKey
    case .registrationFailed:
      "shortcut.error.registrationFailed"
    case .persistenceFailed:
      "shortcut.error.persistenceFailed"
    case .defaultUnavailable:
      "shortcut.error.defaultUnavailable"
    }
  }

  var errorDescription: String? {
    NSLocalizedString(localizationKey, comment: "")
  }
}

enum ShortcutValidator {
  private static let escapeKeyCode = UInt32(kVK_Escape)
  private static let maximumKeyCode: UInt32 = 127
  private static let modifierKeyCodes: Set<UInt32> = [
    UInt32(kVK_Shift),
    UInt32(kVK_RightShift),
    UInt32(kVK_Control),
    UInt32(kVK_RightControl),
    UInt32(kVK_Option),
    UInt32(kVK_RightOption),
    UInt32(kVK_Command),
    UInt32(kVK_RightCommand),
    UInt32(kVK_CapsLock),
    UInt32(kVK_Function)
  ]

  static func validate(_ shortcut: KeyboardShortcut) throws {
    guard shortcut.keyCode != escapeKeyCode else {
      throw ShortcutValidationError.escapeNotAllowed
    }

    guard shortcut.keyCode <= maximumKeyCode,
          !modifierKeyCodes.contains(shortcut.keyCode) else {
      throw ShortcutValidationError.unsupportedKey
    }

    guard shortcut.modifiers.isSubset(of: ShortcutModifiers.persistedMask) else {
      throw ShortcutValidationError.unsupportedModifiers
    }

    guard !shortcut.modifiers.isEmpty else {
      throw ShortcutValidationError.modifierRequired
    }

    let primaryModifiers: ShortcutModifiers = [.command, .option, .control]
    guard !shortcut.modifiers.intersection(primaryModifiers).isEmpty else {
      throw ShortcutValidationError.primaryModifierRequired
    }
  }
}

struct ShortcutStore {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> KeyboardShortcut? {
    guard let keyCode = uint32Value(forKey: Self.keyCodeKey),
          let modifiers = uint32Value(forKey: Self.modifiersKey) else {
      return nil
    }

    let shortcut = KeyboardShortcut(
      keyCode: keyCode,
      modifiers: ShortcutModifiers(rawValue: modifiers)
    )

    return (try? ShortcutValidator.validate(shortcut)) == nil ? nil : shortcut
  }

  func save(_ shortcut: KeyboardShortcut) throws {
    try ShortcutValidator.validate(shortcut)
    defaults.set(Int(shortcut.keyCode), forKey: Self.keyCodeKey)
    defaults.set(Int(shortcut.modifiers.rawValue), forKey: Self.modifiersKey)
  }

  func clear() {
    defaults.removeObject(forKey: Self.keyCodeKey)
    defaults.removeObject(forKey: Self.modifiersKey)
  }

  private static let keyCodeKey = "shortcut.keyCode"
  private static let modifiersKey = "shortcut.modifiers"

  private func uint32Value(forKey key: String) -> UInt32? {
    guard let number = defaults.object(forKey: key) as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return nil
    }

    switch String(cString: number.objCType) {
    case "c", "s", "i", "l", "q":
      let value = number.int64Value
      guard value >= 0, value <= Int64(UInt32.max) else {
        return nil
      }
      return UInt32(value)
    case "C", "S", "I", "L", "Q":
      let value = number.uint64Value
      guard value <= UInt64(UInt32.max) else {
        return nil
      }
      return UInt32(value)
    default:
      return nil
    }
  }
}

enum ShortcutRecordingOutcome: Equatable {
  case cancelled
  case recorded(KeyboardShortcut)
  case rejected(ShortcutValidationError)
}

enum ShortcutRecorderLogic {
  static func outcome(keyCode: UInt32, modifiers: ShortcutModifiers) -> ShortcutRecordingOutcome {
    if keyCode == UInt32(kVK_Escape) {
      return .cancelled
    }

    let shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
    do {
      try ShortcutValidator.validate(shortcut)
      return .recorded(shortcut)
    } catch let error as ShortcutValidationError {
      return .rejected(error)
    } catch {
      return .rejected(.unsupportedKey)
    }
  }
}

@MainActor
final class ShortcutManager {
  private let store: ShortcutStore
  private let registrar: HotKeyRegistering
  private let handler: () -> Void

  private(set) var currentShortcut: KeyboardShortcut?
  private(set) var error: ShortcutManagerError?

  init(
    store: ShortcutStore,
    registrar: HotKeyRegistering,
    handler: @escaping () -> Void
  ) {
    self.store = store
    self.registrar = registrar
    self.handler = handler
  }

  func registerOnLaunch() {
    let storedShortcut = store.load()
    let candidate = storedShortcut ?? .defaultShortcut

    guard register(candidate) else {
      if candidate != .defaultShortcut, register(.defaultShortcut) {
        persist(.defaultShortcut)
      } else {
        error = .defaultUnavailable
      }
      return
    }

    persist(candidate)
  }

  @discardableResult
  func setShortcut(_ shortcut: KeyboardShortcut) -> Bool {
    do {
      try ShortcutValidator.validate(shortcut)
    } catch let validationError as ShortcutValidationError {
      error = .validation(validationError)
      return false
    } catch _ {
      error = .validation(.unsupportedKey)
      return false
    }

    let previousShortcut = currentShortcut
    do {
      try registrar.registerPrimary(shortcut, handler: handler)
    } catch _ {
      if let previousShortcut, !registrar.isPrimaryRegistered {
        try? registrar.registerPrimary(previousShortcut, handler: handler)
      }
      error = .registrationFailed
      return false
    }

    do {
      try store.save(shortcut)
    } catch _ {
      if let previousShortcut {
        try? registrar.registerPrimary(previousShortcut, handler: handler)
        currentShortcut = previousShortcut
      }
      error = .persistenceFailed
      return false
    }

    currentShortcut = shortcut
    error = nil
    return true
  }

  @discardableResult
  func resetToDefault() -> Bool {
    setShortcut(.defaultShortcut)
  }

  func clearShortcut() {
    registrar.unregisterPrimary()
    store.clear()
    currentShortcut = nil
    error = nil
  }

  private func register(_ shortcut: KeyboardShortcut) -> Bool {
    do {
      try registrar.registerPrimary(shortcut, handler: handler)
      currentShortcut = shortcut
      error = nil
      return true
    } catch _ {
      currentShortcut = nil
      return false
    }
  }

  private func persist(_ shortcut: KeyboardShortcut) {
    do {
      try store.save(shortcut)
      currentShortcut = shortcut
      error = nil
    } catch _ {
      error = .persistenceFailed
    }
  }
}
