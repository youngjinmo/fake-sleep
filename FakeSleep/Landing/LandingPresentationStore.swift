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

  func setShowsAtLaunch(_ value: Bool) {
    defaults.set(value, forKey: Self.showsAtLaunchKey)
  }
}

typealias LandingDisplayStore = LandingPresentationStore
