import Foundation

enum FakeSleepState: Equatable {
  case inactive
  case awaitingSystemLock
  case preparingBlackout
  case active
  // Compatibility cases retained for clients that pattern-match the original
  // blackout-only API. New code should use `inactive` and `active`.
  case awake
  case fakeSleeping

  static func == (lhs: FakeSleepState, rhs: FakeSleepState) -> Bool {
    switch (lhs, rhs) {
    case (.inactive, .inactive), (.inactive, .awake),
         (.awake, .inactive), (.awake, .awake):
      return true
    case (.active, .active), (.active, .fakeSleeping),
         (.fakeSleeping, .active), (.fakeSleeping, .fakeSleeping):
      return true
    case (.awaitingSystemLock, .awaitingSystemLock),
         (.preparingBlackout, .preparingBlackout):
      return true
    default:
      return false
    }
  }
}

enum FakeSleepError: Equatable, LocalizedError {
  case noRestorePath
  case noScreens
  case incompleteOverlayCoverage
  case emergencyEscapeUnavailable
  case batteryBelowCutoff(percent: Int, cutoff: Int)
  case lockTimedOut

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
    case .batteryBelowCutoff:
      "fakeSleep.error.batteryBelowCutoff"
    case .lockTimedOut:
      "fakeSleep.error.lockTimedOut"
    }
  }

  var errorDescription: String? {
    NSLocalizedString(localizationKey, comment: "")
  }
}
