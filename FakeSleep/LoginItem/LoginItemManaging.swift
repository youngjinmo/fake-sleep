enum LoginItemStatus: Equatable {
  case disabled
  case enabled
  case requiresApproval
  case unavailable
}

@MainActor
protocol LoginItemManaging: AnyObject {
  var status: LoginItemStatus { get }
  func setEnabled(_ enabled: Bool) throws
  func openSystemSettings()
}
