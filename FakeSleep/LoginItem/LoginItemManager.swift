import ServiceManagement

@MainActor
protocol LoginItemService {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
  func openSystemSettings()
}

@MainActor
final class MainAppLoginItemService: LoginItemService {
  private let service = SMAppService.mainApp

  var status: SMAppService.Status {
    service.status
  }

  func register() throws {
    try service.register()
  }

  func unregister() throws {
    try service.unregister()
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}

@MainActor
final class LoginItemManager: LoginItemManaging {
  private let service: LoginItemService

  private(set) var status: LoginItemStatus

  init(service: LoginItemService = MainAppLoginItemService()) {
    self.service = service
    self.status = Self.mapStatus(service.status)
  }

  static func mapStatus(_ status: SMAppService.Status) -> LoginItemStatus {
    switch status {
    case .notRegistered:
      .disabled
    case .enabled:
      .enabled
    case .requiresApproval:
      .requiresApproval
    case .notFound:
      .unavailable
    @unknown default:
      .unavailable
    }
  }

  func refreshStatus() {
    status = Self.mapStatus(service.status)
  }

  func setEnabled(_ enabled: Bool) throws {
    defer {
      refreshStatus()
    }

    if enabled {
      try service.register()
    } else {
      try service.unregister()
    }
  }

  func openSystemSettings() {
    service.openSystemSettings()
  }
}
