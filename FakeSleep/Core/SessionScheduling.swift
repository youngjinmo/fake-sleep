import Foundation

@MainActor
protocol SessionScheduling: AnyObject {
  var now: TimeInterval { get }
  @discardableResult
  func schedule(after interval: TimeInterval, _ callback: @escaping () -> Void) -> UUID
  func cancel()
}

@MainActor
final class MonotonicSessionScheduler: SessionScheduling {
  private var timers: [UUID: Timer] = [:]
  private var callbacks: [UUID: () -> Void] = [:]

  var now: TimeInterval {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
  }

  @discardableResult
  func schedule(after interval: TimeInterval, _ callback: @escaping () -> Void) -> UUID {
    let id = UUID()
    let delay = max(0, interval)
    let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
      guard let self else { return }
      self.timers.removeValue(forKey: id)
      let callback = self.callbacks.removeValue(forKey: id)
      callback?()
    }
    timers[id] = timer
    callbacks[id] = callback
    return id
  }

  func cancel() {
    timers.values.forEach { $0.invalidate() }
    timers.removeAll()
    callbacks.removeAll()
  }
}

typealias SystemSessionScheduler = MonotonicSessionScheduler
