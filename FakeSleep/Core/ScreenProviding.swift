import CoreGraphics

struct ScreenDescriptor: Equatable, Hashable {
  let id: UInt32
  let frame: CGRect
}

@MainActor
protocol ScreenProviding {
  func currentScreens() -> [ScreenDescriptor]
}
