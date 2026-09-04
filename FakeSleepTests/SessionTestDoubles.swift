import AppKit
import Foundation
@testable import FakeSleep

@MainActor
final class SessionSleepPreventerSpy: SleepPreventing {
  enum Event: Equatable { case begin, end }
  private(set) var events: [Event] = []
  private(set) var isActive = false

  func begin() {
    guard !isActive else { return }
    isActive = true
    events.append(.begin)
  }

  func end() {
    guard isActive else { return }
    isActive = false
    events.append(.end)
  }
}

@MainActor
final class SessionPowerMonitorSpy: PowerMonitoring {
  var currentSnapshot: PowerSnapshot
  private(set) var stopCount = 0
  private var onChange: ((PowerSnapshot) -> Void)?

  init(snapshot: PowerSnapshot) {
    currentSnapshot = snapshot
  }

  func start(_ onChange: @escaping (PowerSnapshot) -> Void) {
    self.onChange = onChange
  }

  func stop() {
    stopCount += 1
    onChange = nil
  }

  func emit(_ snapshot: PowerSnapshot) {
    currentSnapshot = snapshot
    onChange?(snapshot)
  }
}

@MainActor
final class SessionSchedulerSpy: SessionScheduling {
  var now: TimeInterval = 0
  private(set) var cancelCount = 0
  private(set) var scheduledIntervals: [TimeInterval] = []
  private var callbacks: [() -> Void] = []

  @discardableResult
  func schedule(after interval: TimeInterval, _ callback: @escaping () -> Void) -> UUID {
    scheduledIntervals.append(interval)
    callbacks.append(callback)
    return UUID()
  }

  func cancel() {
    cancelCount += 1
    callbacks.removeAll()
  }

  func fireNext() {
    guard !callbacks.isEmpty else { return }
    callbacks.removeFirst()()
  }

  func fire(at index: Int) {
    guard callbacks.indices.contains(index) else { return }
    callbacks.remove(at: index)()
  }
}

@MainActor
final class SessionOverlayPresenterSpy: OverlayPresenting {
  var coveredScreenIDs: Set<UInt32>
  private(set) var removeAllCount = 0
  private(set) var restoreHintEvents: [(visible: Bool, animated: Bool)] = []

  init(coveredScreenIDs: Set<UInt32> = []) {
    self.coveredScreenIDs = coveredScreenIDs
  }

  func reconcile(with screens: [ScreenDescriptor]) {
    // A non-empty initial set intentionally models partial coverage.
    if coveredScreenIDs.isEmpty {
      coveredScreenIDs = Set(screens.map(\.id))
    }
  }

  func removeAll() {
    removeAllCount += 1
    coveredScreenIDs = []
  }

  func setRestoreHintVisible(_ visible: Bool, animated: Bool) {
    restoreHintEvents.append((visible: visible, animated: animated))
  }
}

@MainActor
final class SessionScreenProviderSpy: ScreenProviding {
  let screens: [ScreenDescriptor]

  init(screens: [ScreenDescriptor]) {
    self.screens = screens
  }

  func currentScreens() -> [ScreenDescriptor] { screens }
}

@MainActor
final class SessionHotKeyRegistrarSpy: HotKeyRegistering {
  var isPrimaryRegistered = true
  var emergencyRegistrationSucceeds = true
  func registerPrimary(_ shortcut: KeyboardShortcut, handler: @escaping () -> Void) throws {}
  func registerEmergencyEscape(handler: @escaping () -> Void) throws {
    guard emergencyRegistrationSucceeds else { throw SessionHotKeyRegistrationError.unavailable }
  }
  func unregisterEmergencyEscape() {}
}

private enum SessionHotKeyRegistrationError: Error {
  case unavailable
}

@MainActor
final class SessionCursorSpy: CursorManaging {
  func hide() {}
  func unhide() {}
}
