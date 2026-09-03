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
