import Carbon.HIToolbox

@MainActor
final class CarbonHotKeyController: HotKeyRegistering {
  private enum HotKeyIdentifier {
    static let primary: UInt32 = 1
    static let emergencyEscape: UInt32 = 2
  }

  nonisolated(unsafe) private var applicationEventHandler: EventHandlerRef? = nil
  private var eventHandlerError: CarbonHotKeyError? = nil
  nonisolated(unsafe) private var primaryHotKey: EventHotKeyRef? = nil
  nonisolated(unsafe) private var emergencyEscapeHotKey: EventHotKeyRef? = nil
  private var primaryHandler: (() -> Void)?
  private var emergencyEscapeHandler: (() -> Void)?
  private var primaryShortcut: KeyboardShortcut?

  private(set) var isPrimaryRegistered = false

  init() {
    var eventType = EventTypeSpec(
      eventClass: UInt32(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    var handler: EventHandlerRef?
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      carbonApplicationEventHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &handler
    )

    if status == noErr, let handler {
      applicationEventHandler = handler
      eventHandlerError = nil
    } else {
      if let handler {
        RemoveEventHandler(handler)
      }
      applicationEventHandler = nil
      eventHandlerError = status == noErr
        ? .eventHandlerUnavailable
        : .eventHandlerInstallationFailed(status)
    }
  }

  func registerPrimary(_ shortcut: KeyboardShortcut, handler: @escaping () -> Void) throws {
    let previousShortcut = primaryShortcut
    let previousHandler = primaryHandler
    unregisterPrimary()

    do {
      let hotKey = try registerHotKey(
        keyCode: shortcut.keyCode,
        modifiers: carbonModifiers(for: shortcut.modifiers),
        identifier: HotKeyIdentifier.primary
      )
      primaryHotKey = hotKey
      primaryShortcut = shortcut
      primaryHandler = handler
      isPrimaryRegistered = true
    } catch {
      if let previousShortcut, let previousHandler {
        restorePrimary(shortcut: previousShortcut, handler: previousHandler)
      }
      throw error
    }
  }

  func registerEmergencyEscape(handler: @escaping () -> Void) throws {
    unregisterEmergencyEscape()

    let hotKey = try registerHotKey(
      keyCode: UInt32(kVK_Escape),
      modifiers: 0,
      identifier: HotKeyIdentifier.emergencyEscape
    )
    emergencyEscapeHotKey = hotKey
    emergencyEscapeHandler = handler
  }

  func unregisterEmergencyEscape() {
    if let emergencyEscapeHotKey {
      UnregisterEventHotKey(emergencyEscapeHotKey)
    }
    emergencyEscapeHotKey = nil
    emergencyEscapeHandler = nil
  }

  deinit {
    if let primaryHotKey {
      UnregisterEventHotKey(primaryHotKey)
    }
    if let emergencyEscapeHotKey {
      UnregisterEventHotKey(emergencyEscapeHotKey)
    }
    if let applicationEventHandler {
      RemoveEventHandler(applicationEventHandler)
    }
  }

  private func registerHotKey(
    keyCode: UInt32,
    modifiers: UInt32,
    identifier: UInt32
  ) throws -> EventHotKeyRef {
    guard eventHandlerError == nil, applicationEventHandler != nil else {
      throw eventHandlerError ?? CarbonHotKeyError.eventHandlerUnavailable
    }

    let hotKeyID = EventHotKeyID(
      signature: OSType(0x46534C50),
      id: identifier
    )
    var hotKey: EventHotKeyRef?
    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKey
    )

    guard status == noErr, let hotKey else {
      if let hotKey {
        UnregisterEventHotKey(hotKey)
      }
      if status == noErr {
        throw CarbonHotKeyError.hotKeyReferenceUnavailable
      }
      throw CarbonHotKeyError.registrationFailed(status)
    }

    return hotKey
  }

  private func restorePrimary(shortcut: KeyboardShortcut, handler: @escaping () -> Void) {
    do {
      let hotKey = try registerHotKey(
        keyCode: shortcut.keyCode,
        modifiers: carbonModifiers(for: shortcut.modifiers),
        identifier: HotKeyIdentifier.primary
      )
      primaryHotKey = hotKey
      primaryShortcut = shortcut
      primaryHandler = handler
      isPrimaryRegistered = true
    } catch {
      isPrimaryRegistered = false
    }
  }

  func unregisterPrimary() {
    if let primaryHotKey {
      UnregisterEventHotKey(primaryHotKey)
    }
    primaryHotKey = nil
    primaryShortcut = nil
    primaryHandler = nil
    isPrimaryRegistered = false
  }

  private func carbonModifiers(for modifiers: ShortcutModifiers) -> UInt32 {
    var carbonModifiers: UInt32 = 0
    if modifiers.contains(.command) {
      carbonModifiers |= UInt32(cmdKey)
    }
    if modifiers.contains(.option) {
      carbonModifiers |= UInt32(optionKey)
    }
    if modifiers.contains(.control) {
      carbonModifiers |= UInt32(controlKey)
    }
    if modifiers.contains(.shift) {
      carbonModifiers |= UInt32(shiftKey)
    }
    return carbonModifiers
  }

  fileprivate func handleHotKey(identifier: UInt32) {
    switch identifier {
    case HotKeyIdentifier.primary:
      primaryHandler?()
    case HotKeyIdentifier.emergencyEscape:
      emergencyEscapeHandler?()
    default:
      break
    }
  }
}

private enum CarbonHotKeyError: Error {
  case eventHandlerUnavailable
  case eventHandlerInstallationFailed(OSStatus)
  case hotKeyReferenceUnavailable
  case registrationFailed(OSStatus)
}

private func carbonApplicationEventHandler(
  _ nextHandler: EventHandlerCallRef?,
  _ event: EventRef?,
  _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event, let userData else {
    return OSStatus(eventNotHandledErr)
  }

  var hotKeyID = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &hotKeyID
  )
  guard status == noErr else { return status }

  let controller = Unmanaged<CarbonHotKeyController>
    .fromOpaque(userData)
    .takeUnretainedValue()
  let identifier = hotKeyID.id
  Task { @MainActor [weak controller] in
    controller?.handleHotKey(identifier: identifier)
  }
  return noErr
}
