import AppKit

@MainActor
final class SystemScreenProvider: ScreenProviding {
  static func descriptor(screenNumber: NSNumber?, frame: CGRect) -> ScreenDescriptor? {
    guard let screenNumber else { return nil }

    let value = screenNumber.doubleValue
    guard value.isFinite,
          value >= 0,
          value <= Double(UInt32.max),
          value.rounded() == value,
          let screenID = UInt32(exactly: value) else {
      return nil
    }

    return ScreenDescriptor(id: screenID, frame: frame)
  }

  func currentScreens() -> [ScreenDescriptor] {
    NSScreen.screens.compactMap { screen in
      let screenNumber = screen.deviceDescription[
        NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
      ] as? NSNumber
      return Self.descriptor(screenNumber: screenNumber, frame: screen.frame)
    }
  }
}
