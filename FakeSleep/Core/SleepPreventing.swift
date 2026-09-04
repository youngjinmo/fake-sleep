import Foundation

@MainActor
protocol SleepPreventing: AnyObject {
  var isActive: Bool { get }
  func begin()
  func end()
}

@MainActor
final class ProcessInfoSleepPreventer: SleepPreventing {
  private var activity: NSObjectProtocol?

  var isActive: Bool { activity != nil }

  func begin() {
    guard activity == nil else { return }
    activity = ProcessInfo.processInfo.beginActivity(
      options: .idleSystemSleepDisabled,
      reason: "Fake Sleep keeps the Mac available while you are away"
    )
  }

  func end() {
    guard let activity else { return }
    ProcessInfo.processInfo.endActivity(activity)
    self.activity = nil
  }
}

typealias SystemSleepPreventer = ProcessInfoSleepPreventer
