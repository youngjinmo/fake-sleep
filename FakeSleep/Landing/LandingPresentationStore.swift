import Foundation

struct LandingPresentationStore {
  private static let showsAtLaunchKey = "com.example.FakeSleep.landing.showsAtLaunch"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var showsAtLaunch: Bool {
    defaults.object(forKey: Self.showsAtLaunchKey) as? Bool ?? true
  }

  var shouldShowAtLaunch: Bool {
    get { showsAtLaunch }
    nonmutating set { setShowsAtLaunch(newValue) }
  }

  /// Whether the current onboarding needs to be shown when the app launches.
  ///
  /// `showsAtLaunch` is retained as a source-compatible read/write property for
  /// older clients, but it is intentionally not consulted by the onboarding
  /// flow.  A completed onboarding version is the only launch policy now.
  var shouldShowOnboarding: Bool {
    onboardingVersion < SessionSettingsStore.onboardingVersion
  }

  var onboardingVersion: Int {
    settingsStore.onboardingVersion
  }

  var isOnboardingCompleted: Bool {
    !shouldShowOnboarding
  }

  var settingsStore: SessionSettingsStore {
    SessionSettingsStore(defaults: defaults)
  }

  func markOnboardingCompleted(version: Int = SessionSettingsStore.onboardingVersion) {
    settingsStore.markOnboardingCompleted(version: version)
  }

  func setShowsAtLaunch(_ value: Bool) {
    defaults.set(value, forKey: Self.showsAtLaunchKey)
  }
}

typealias LandingDisplayStore = LandingPresentationStore
