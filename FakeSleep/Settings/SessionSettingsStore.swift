import Foundation

struct SessionSettingsStore {
  static let onboardingVersion = 1

  private enum Key {
    static let onboardingVersion = "onboarding.version"
    static let defaultMode = "session.defaultMode"
    static let defaultDuration = "session.defaultDuration"
    static let batteryCutoffPercent = "session.batteryCutoffPercent"
    static let blackoutSafetyIntroShown = "blackout.safetyIntroShown"
  }

  static let defaultSettings = SessionSettings(
    defaultMode: .secureLeave,
    defaultDuration: .indefinite,
    batteryCutoffPercent: 10
  )

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var settings: SessionSettings {
    let mode = loadMode() ?? Self.defaultSettings.defaultMode
    let duration = loadDuration() ?? Self.defaultSettings.defaultDuration
    let cutoff = loadBatteryCutoff() ?? Self.defaultSettings.batteryCutoffPercent
    return SessionSettings(
      defaultMode: mode,
      defaultDuration: duration,
      batteryCutoffPercent: cutoff
    )
  }

  var isOnboardingCompleted: Bool {
    onboardingVersion >= Self.onboardingVersion
  }

  var onboardingVersion: Int {
    guard let value = integerValue(forKey: Key.onboardingVersion), value >= 0 else {
      return 0
    }
    return value
  }

  var isBlackoutSafetyIntroShown: Bool {
    defaults.bool(forKey: Key.blackoutSafetyIntroShown)
  }

  func save(_ settings: SessionSettings) {
    let normalized = Self.normalized(settings)
    defaults.set(normalized.defaultMode.rawValue, forKey: Key.defaultMode)
    if let data = try? encoder.encode(normalized.defaultDuration) {
      defaults.set(data, forKey: Key.defaultDuration)
    }
    defaults.set(normalized.batteryCutoffPercent, forKey: Key.batteryCutoffPercent)
  }

  func setMode(_ mode: FakeSleepMode) {
    save(
      SessionSettings(
        defaultMode: mode,
        defaultDuration: settings.defaultDuration,
        batteryCutoffPercent: settings.batteryCutoffPercent
      )
    )
  }

  func setDuration(_ duration: SessionDuration) {
    save(
      SessionSettings(
        defaultMode: settings.defaultMode,
        defaultDuration: duration,
        batteryCutoffPercent: settings.batteryCutoffPercent
      )
    )
  }

  func setBatteryCutoffPercent(_ percent: Int) {
    guard (0...100).contains(percent) else {
      let current = settings
      save(
        SessionSettings(
          defaultMode: current.defaultMode,
          defaultDuration: current.defaultDuration,
          batteryCutoffPercent: Self.defaultSettings.batteryCutoffPercent
        )
      )
      return
    }
    save(
      SessionSettings(
        defaultMode: settings.defaultMode,
        defaultDuration: settings.defaultDuration,
        batteryCutoffPercent: percent
      )
    )
  }

  func markOnboardingCompleted(version: Int = Self.onboardingVersion) {
    guard version >= 0 else { return }
    defaults.set(version, forKey: Key.onboardingVersion)
  }

  func setBlackoutSafetyIntroShown(_ shown: Bool) {
    defaults.set(shown, forKey: Key.blackoutSafetyIntroShown)
  }

  func cancelOnboarding() {
    // Onboarding edits are kept in the view model until completion. This method
    // intentionally does not touch persisted settings or the completion marker.
  }

  private func loadMode() -> FakeSleepMode? {
    guard let rawValue = defaults.string(forKey: Key.defaultMode) else { return nil }
    return FakeSleepMode(rawValue: rawValue)
  }

  private func loadDuration() -> SessionDuration? {
    guard let data = defaults.data(forKey: Key.defaultDuration) else { return nil }
    return try? decoder.decode(SessionDuration.self, from: data)
  }

  private func loadBatteryCutoff() -> Int? {
    guard let value = integerValue(forKey: Key.batteryCutoffPercent), (0...100).contains(value) else {
      return nil
    }
    return value
  }

  private func integerValue(forKey key: String) -> Int? {
    guard let value = defaults.object(forKey: key) as? NSNumber,
          CFGetTypeID(value) != CFBooleanGetTypeID() else {
      return nil
    }
    return value.intValue
  }

  private static func normalized(_ settings: SessionSettings) -> SessionSettings {
    SessionSettings(
      defaultMode: settings.defaultMode,
      defaultDuration: normalizedDuration(settings.defaultDuration),
      batteryCutoffPercent: (0...100).contains(settings.batteryCutoffPercent)
        ? settings.batteryCutoffPercent
        : defaultSettings.batteryCutoffPercent
    )
  }

  private static func normalizedDuration(_ duration: SessionDuration) -> SessionDuration {
    switch duration {
    case .indefinite:
      return .indefinite
    case .minutes(let minutes):
      return minutes > 0 ? .minutes(minutes) : .indefinite
    }
  }
}
