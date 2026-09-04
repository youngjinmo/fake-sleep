import Foundation
import IOKit.ps

@MainActor
protocol PowerMonitoring: AnyObject {
  var currentSnapshot: PowerSnapshot { get }
  func start(_ onChange: @escaping (PowerSnapshot) -> Void)
  func stop()
}

@MainActor
final class IOKitPowerMonitor: PowerMonitoring {
  private(set) var currentSnapshot: PowerSnapshot
  private var changeHandler: ((PowerSnapshot) -> Void)?
  private var pollingTimer: Timer?

  init() {
    currentSnapshot = Self.readSnapshot()
  }

  func start(_ onChange: @escaping (PowerSnapshot) -> Void) {
    stop()
    changeHandler = onChange
    currentSnapshot = Self.readSnapshot()
    pollingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      guard let self else { return }
      let snapshot = Self.readSnapshot()
      guard snapshot != self.currentSnapshot else { return }
      self.currentSnapshot = snapshot
      self.changeHandler?(snapshot)
    }
  }

  func stop() {
    pollingTimer?.invalidate()
    pollingTimer = nil
    changeHandler = nil
  }

  static func readSnapshot() -> PowerSnapshot {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
      return PowerSnapshot(isUsingBattery: false, batteryPercent: nil)
    }

    let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue()
    let count = CFArrayGetCount(sources)
    guard count > 0 else {
      return PowerSnapshot(isUsingBattery: false, batteryPercent: nil)
    }

    var foundBattery = false
    var batteryPercent: Int?
    for index in 0..<count {
      let source = CFArrayGetValueAtIndex(sources, index)
      guard let source else { continue }
      let sourceRef = unsafeBitCast(source, to: CFTypeRef.self)
      guard let description = IOPSGetPowerSourceDescription(blob, sourceRef)?.takeUnretainedValue()
          as? [String: Any] else {
        continue
      }

      let state = description[kIOPSPowerSourceStateKey] as? String
      guard state == kIOPSBatteryPowerValue else { continue }
      foundBattery = true

      let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue
      let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.intValue
      guard let current, let maximum, maximum > 0 else { continue }
      let percentage = Int((Double(current) / Double(maximum) * 100).rounded(.down))
      batteryPercent = min(max(percentage, 0), 100)
      break
    }

    return PowerSnapshot(isUsingBattery: foundBattery, batteryPercent: batteryPercent)
  }
}

typealias SystemPowerMonitor = IOKitPowerMonitor
