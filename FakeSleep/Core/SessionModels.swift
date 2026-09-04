import Foundation

enum FakeSleepMode: String, Codable, CaseIterable {
  case secureLeave
  case blackout
}

enum SessionDuration: Equatable, Codable, CaseIterable {
  case minutes(Int)
  case indefinite

  static var allCases: [SessionDuration] { presets }

  static var presets: [SessionDuration] {
    [.minutes(30), .minutes(60), .minutes(120), .minutes(240), .indefinite]
  }

  var interval: TimeInterval? {
    switch self {
    case .minutes(let minutes):
      guard minutes > 0 else { return nil }
      return TimeInterval(minutes * 60)
    case .indefinite:
      return nil
    }
  }

  var minutesValue: Int? {
    guard case .minutes(let minutes) = self else { return nil }
    return minutes
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case minutes
  }

  private enum Kind: String, Codable {
    case minutes
    case indefinite
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .kind)
    switch kind {
    case .minutes:
      let minutes = try container.decode(Int.self, forKey: .minutes)
      guard minutes > 0 else {
        throw DecodingError.dataCorruptedError(
          forKey: .minutes,
          in: container,
          debugDescription: "Session duration must be positive"
        )
      }
      self = .minutes(minutes)
    case .indefinite:
      self = .indefinite
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .minutes(let minutes):
      try container.encode(Kind.minutes, forKey: .kind)
      try container.encode(minutes, forKey: .minutes)
    case .indefinite:
      try container.encode(Kind.indefinite, forKey: .kind)
    }
  }
}

struct SessionConfiguration: Equatable, Codable {
  let mode: FakeSleepMode
  let duration: SessionDuration
  let batteryCutoffPercent: Int

  init(
    mode: FakeSleepMode,
    duration: SessionDuration,
    batteryCutoffPercent: Int
  ) {
    self.mode = mode
    self.duration = duration
    self.batteryCutoffPercent = batteryCutoffPercent
  }
}

struct SessionSettings: Equatable, Codable {
  let defaultMode: FakeSleepMode
  let defaultDuration: SessionDuration
  let batteryCutoffPercent: Int

  init(
    defaultMode: FakeSleepMode,
    defaultDuration: SessionDuration,
    batteryCutoffPercent: Int
  ) {
    self.defaultMode = defaultMode
    self.defaultDuration = defaultDuration
    self.batteryCutoffPercent = batteryCutoffPercent
  }

  var configuration: SessionConfiguration {
    SessionConfiguration(
      mode: defaultMode,
      duration: defaultDuration,
      batteryCutoffPercent: batteryCutoffPercent
    )
  }
}

struct PowerSnapshot: Equatable {
  let isUsingBattery: Bool
  let batteryPercent: Int?

  init(isUsingBattery: Bool, batteryPercent: Int?) {
    self.isUsingBattery = isUsingBattery
    self.batteryPercent = batteryPercent.map { min(max($0, 0), 100) }
  }
}

enum SessionLockState: Equatable {
  case unlocked
  case locked
  case unknown
}

struct FakeSleepSession: Equatable, Identifiable {
  let id: UUID
  let mode: FakeSleepMode
  let startedAt: Date
  let monotonicDeadline: TimeInterval?
  let scheduledEndDate: Date?
  let batteryCutoffPercent: Int
  var lockState: SessionLockState

  init(
    id: UUID = UUID(),
    mode: FakeSleepMode,
    startedAt: Date = Date(),
    monotonicDeadline: TimeInterval?,
    scheduledEndDate: Date?,
    batteryCutoffPercent: Int,
    lockState: SessionLockState = .unlocked
  ) {
    self.id = id
    self.mode = mode
    self.startedAt = startedAt
    self.monotonicDeadline = monotonicDeadline
    self.scheduledEndDate = scheduledEndDate
    self.batteryCutoffPercent = batteryCutoffPercent
    self.lockState = lockState
  }
}

typealias CurrentSession = FakeSleepSession

enum SessionEndReason: Equatable {
  case manual
  case timerExpired
  case lowBattery(percent: Int)
  case lockTimedOut
  case activationFailed(FakeSleepError)
}
