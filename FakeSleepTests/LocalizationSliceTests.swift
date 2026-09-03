import AppKit
import Foundation
import XCTest

final class LocalizationSliceTests: XCTestCase {
  private let requiredLocalizationKeys = [
    // Menu titles and status item.
    "menu.startFakeSleep",
    "menu.restoreDisplays",
    "menu.settings",
    "menu.quitFakeSleep",
    "menu.accessibilityLabel",
    "menu.restoreAccessibilityLabel",
    "menu.tooltip",
    "menu.restoreTooltip",
    // Settings labels, buttons, and shortcut recording UI.
    "settings.title",
    "settings.shortcut",
    "settings.resetDefault",
    "settings.launchAtLogin",
    "settings.loginApprovalRequired",
    "settings.openLoginItemsSettings",
    "shortcut.record.prompt",
    "shortcut.record.none",
    "shortcut.record.button",
    "shortcut.record.cancel",
    "shortcut.record.accessibilityLabel",
    // Shortcut validation, registration, and persistence errors.
    "shortcut.error.keyRequired",
    "shortcut.error.modifierRequired",
    "shortcut.error.primaryModifierRequired",
    "shortcut.error.unsupportedKey",
    "shortcut.error.unsupportedModifiers",
    "shortcut.error.escapeNotAllowed",
    "shortcut.error.registrationFailed",
    "shortcut.error.persistenceFailed",
    "shortcut.error.defaultUnavailable",
    // Login-item statuses and approval guidance.
    "loginItem.status.disabled",
    "loginItem.status.enabled",
    "loginItem.status.requiresApproval",
    "loginItem.status.unavailable",
    // Coordinator errors.
    "fakeSleep.error.noRestorePath",
    "fakeSleep.error.noScreens",
    "fakeSleep.error.incompleteOverlayCoverage",
    "fakeSleep.error.emergencyEscapeUnavailable",
  ]

  func testLocalizableCatalog에는필수키와영어한국어비어있지않은값이있다() throws {
    // Given: 앱 번들 또는 저장소의 Localizable String Catalog를 읽는다.
    let catalog = try loadJSONResource(named: "Localizable", ext: "xcstrings")

    // When: 구현 계약에 정의된 모든 키의 영어/한국어 값을 확인한다.
    let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
    for key in requiredLocalizationKeys {
      let entry = try XCTUnwrap(strings[key] as? [String: Any], "누락된 localization key: \(key)")
      let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
      for language in ["en", "ko"] {
        let localization = try XCTUnwrap(
          localizations[language] as? [String: Any],
          "\(key)의 \(language) localization이 없습니다"
        )
        let stringUnit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
        let value = try XCTUnwrap(stringUnit["value"] as? String)

        // Then: 양쪽 언어의 실제 표시 문자열은 공백이 아니다.
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "비어 있는 \(language) localization: \(key)")
      }
    }
  }

  func testAppIcon에는완전한macOS슬롯과실제텍스트없는artwork파일참조가있다() throws {
    // Given: AppIcon Contents.json과 그것이 참조하는 artwork를 찾는다.
    let contentsURL = try resourceURL(
      relativePath: "FakeSleep/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
      bundleResource: "AppIcon.appiconset/Contents",
      bundleExtension: "json"
    )
    let contents = try json(at: contentsURL)
    let images = try XCTUnwrap(contents["images"] as? [[String: Any]])
    let expectedSlots: Set<String> = [
      "16x16@1x", "16x16@2x", "32x32@1x", "32x32@2x",
      "128x128@1x", "128x128@2x", "256x256@1x", "256x256@2x",
      "512x512@1x", "512x512@2x",
    ]

    // When: macOS icon slots와 파일명을 수집한다.
    let actualSlots = Set(images.map { "\($0["size"] as? String ?? "")@\($0["scale"] as? String ?? "")" })
    let filenames = try images.map { image -> String in
      let idiom = try XCTUnwrap(image["idiom"] as? String)
      XCTAssertEqual(idiom, "mac")
      let filename = try XCTUnwrap(image["filename"] as? String, "AppIcon 슬롯에 filename이 없습니다")
      XCTAssertFalse(filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      XCTAssertFalse(filename.lowercased().contains("placeholder"))
      XCTAssertFalse(filename.lowercased().contains("symbol"), "SF Symbol을 AppIcon artwork로 사용할 수 없습니다")
      return filename
    }

    // Then: 모든 슬롯이 정확히 존재하고, 각 참조가 읽을 수 있는 이미지 파일이다.
    XCTAssertEqual(actualSlots, expectedSlots)
    XCTAssertEqual(Set(filenames).count, filenames.count)
    for filename in filenames {
      let artworkURL = contentsURL.deletingLastPathComponent().appendingPathComponent(filename)
      let data = try Data(contentsOf: artworkURL)
      XCTAssertFalse(data.isEmpty, "빈 AppIcon artwork: \(filename)")
      XCTAssertNotNil(NSImage(data: data), "이미지로 읽을 수 없는 AppIcon artwork: \(filename)")
    }
  }

  func testInfoPlistCatalog에는앱표시이름과plist이름의영어한국어계약이있다() throws {
    // Given: InfoPlist localization catalog를 읽는다.
    let catalog = try loadJSONResource(named: "InfoPlist", ext: "xcstrings")
    let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

    // When: macOS가 표시하는 이름 관련 plist 값을 확인한다.
    for key in ["CFBundleDisplayName", "CFBundleName"] {
      let entry = try XCTUnwrap(strings[key] as? [String: Any], "InfoPlist key 누락: \(key)")
      let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
      for language in ["en", "ko"] {
        let value = try stringValue(localizations[language], key: key, language: language)
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(value, "Fake Sleep", "제품명은 영어/한국어에서 번역하지 않습니다")
      }
    }
  }

  private func stringValue(_ rawLocalization: Any?, key: String, language: String) throws -> String {
    let localization = try XCTUnwrap(rawLocalization as? [String: Any], "\(key)의 \(language) localization 누락")
    let stringUnit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
    return try XCTUnwrap(stringUnit["value"] as? String)
  }

  private func loadJSONResource(named name: String, ext: String) throws -> [String: Any] {
    let url = try resourceURL(relativePath: "FakeSleep/Resources/\(name).\(ext)", bundleResource: name, bundleExtension: ext)
    return try json(at: url)
  }

  private func resourceURL(relativePath: String, bundleResource: String, bundleExtension: String) throws -> URL {
    if let bundleURL = Bundle(for: type(of: self)).url(forResource: bundleResource, withExtension: bundleExtension) {
      return bundleURL
    }
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(relativePath)
    return try XCTUnwrap(FileManager.default.fileExists(atPath: sourceURL.path) ? sourceURL : nil,
                         "리소스를 찾을 수 없습니다: \(relativePath)")
  }

  private func json(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
