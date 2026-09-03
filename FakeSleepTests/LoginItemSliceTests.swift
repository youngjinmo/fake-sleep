import ServiceManagement
import XCTest
@testable import FakeSleep

@available(macOS 13.0, *)
@MainActor
final class LoginItemManagerTests: XCTestCase {
  func testSMAppService상태를모두내부상태로매핑한다() {
    // Given: ServiceManagement가 제공하는 네 가지 상태가 있다.
    let cases: [(SMAppService.Status, LoginItemStatus)] = [
      (.notRegistered, .disabled),
      (.enabled, .enabled),
      (.requiresApproval, .requiresApproval),
      (.notFound, .unavailable)
    ]

    // When: 각 상태를 LoginItemManager의 매핑 helper에 전달한다.
    // Then: 제품 내부 상태가 명세대로 매핑된다.
    for (serviceStatus, expectedStatus) in cases {
      XCTAssertEqual(LoginItemManager.mapStatus(serviceStatus), expectedStatus)
    }
  }

  func testnotRegistered상태로생성하면LaunchatLogin이꺼진상태다() {
    let service = LoginItemServiceFake(status: .notRegistered)

    // Given: 로그인 항목이 등록되지 않았다.
    let manager = LoginItemManager(service: service)

    // When: 초기 상태를 확인한다.
    // Then: Launch at Login은 꺼짐으로 표시된다.
    XCTAssertEqual(manager.status, .disabled)
  }

  func test외부에서변경된service상태를refreshStatus호출후반영한다() {
    let service = LoginItemServiceFake(status: .requiresApproval)
    let manager = LoginItemManager(service: service)

    // Given: manager가 시스템 설정에서 승인이 필요한 상태를 표시하고 있다.
    XCTAssertEqual(manager.status, .requiresApproval)

    // When: 외부에서 승인이 완료되어 로그인 항목이 활성화된 뒤 상태를 새로 읽는다.
    service.status = .enabled
    manager.refreshStatus()

    // Then: manager가 service의 최신 상태를 표시한다.
    XCTAssertEqual(manager.status, .enabled)
  }

  func test등록성공후service상태를다시읽어활성상태를갱신한다() throws {
    let service = LoginItemServiceFake(status: .notRegistered)
    service.statusAfterRegister = .enabled
    let manager = LoginItemManager(service: service)

    // Given: 등록 전 로그인 항목은 비활성 상태다.
    // When: Launch at Login을 켠다.
    try manager.setEnabled(true)

    // Then: register 이후 service의 최신 상태가 표시된다.
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(manager.status, .enabled)
  }

  func test등록해제성공후service상태를다시읽어비활성상태를갱신한다() throws {
    let service = LoginItemServiceFake(status: .enabled)
    service.statusAfterUnregister = .notRegistered
    let manager = LoginItemManager(service: service)

    // Given: 로그인 항목이 활성화되어 있다.
    // When: Launch at Login을 끈다.
    try manager.setEnabled(false)

    // Then: unregister 이후 service의 최신 상태가 표시된다.
    XCTAssertEqual(service.unregisterCount, 1)
    XCTAssertEqual(manager.status, .disabled)
  }

  func test등록오류가나도service상태를다시읽고오류를던진다() {
    let service = LoginItemServiceFake(status: .requiresApproval)
    service.registerError = .operationFailed
    let manager = LoginItemManager(service: service)

    // Given: 등록 호출은 실패하지만 service의 현재 상태는 승인 필요다.
    // When: Launch at Login 등록을 시도한다.
    XCTAssertThrowsError(try manager.setEnabled(true)) { error in
      XCTAssertEqual(error as? LoginItemServiceError, .operationFailed)
    }

    // Then: 오류를 전달하면서도 service 상태를 표시한다.
    XCTAssertEqual(manager.status, .requiresApproval)
  }

  func test등록해제오류가나도service상태를다시읽고오류를던진다() {
    let service = LoginItemServiceFake(status: .enabled)
    service.unregisterError = .operationFailed
    let manager = LoginItemManager(service: service)

    // Given: 해제 호출은 실패하지만 service의 현재 상태는 활성이다.
    // When: Launch at Login 해제를 시도한다.
    XCTAssertThrowsError(try manager.setEnabled(false)) { error in
      XCTAssertEqual(error as? LoginItemServiceError, .operationFailed)
    }

    // Then: 오류를 전달하면서도 service 상태를 표시한다.
    XCTAssertEqual(manager.status, .enabled)
  }

  func test승인필요상태의시스템설정열기는service로전달된다() {
    let service = LoginItemServiceFake(status: .requiresApproval)
    let manager = LoginItemManager(service: service)

    // Given: 사용자의 승인이 필요한 상태다.
    // When: 로그인 항목 시스템 설정 열기를 요청한다.
    manager.openSystemSettings()

    // Then: 요청이 주입된 service로 전달된다.
    XCTAssertEqual(service.openSystemSettingsCount, 1)
  }
}

@available(macOS 13.0, *)
@MainActor
private final class LoginItemServiceFake: LoginItemService {
  var status: SMAppService.Status
  var statusAfterRegister: SMAppService.Status?
  var statusAfterUnregister: SMAppService.Status?
  var registerError: LoginItemServiceError?
  var unregisterError: LoginItemServiceError?
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0
  private(set) var openSystemSettingsCount = 0

  init(status: SMAppService.Status) {
    self.status = status
  }

  func register() throws {
    registerCount += 1
    if let registerError {
      throw registerError
    }
    if let statusAfterRegister {
      status = statusAfterRegister
    }
  }

  func unregister() throws {
    unregisterCount += 1
    if let unregisterError {
      throw unregisterError
    }
    if let statusAfterUnregister {
      status = statusAfterUnregister
    }
  }

  func openSystemSettings() {
    openSystemSettingsCount += 1
  }
}

private enum LoginItemServiceError: Error, Equatable {
  case operationFailed
}
