import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
  let shortcut: KeyboardShortcut?
  let onRecord: (KeyboardShortcut) -> Void

  @State private var isRecording = false
  @State private var recordingError: ShortcutValidationError?

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      HStack(spacing: 8) {
        Text(
          isRecording
            ? Self.localized("shortcut.record.prompt", fallback: "Press a shortcut…")
            : shortcut.map { KeyboardShortcutFormatter.string(from: $0) }
              ?? Self.localized("shortcut.record.none", fallback: "Not set")
        )
        .frame(minWidth: 90, alignment: .trailing)

        Button(
          isRecording
            ? Self.localized("shortcut.record.cancel", fallback: "Cancel")
            : Self.localized("shortcut.record.button", fallback: "Record")
        ) {
          recordingError = nil
          isRecording.toggle()
        }
        .accessibilityLabel(
          Self.localized("shortcut.record.accessibilityLabel", fallback: "Record shortcut")
        )
      }

      ShortcutCaptureView(isRecording: $isRecording) { keyCode, modifiers in
        switch ShortcutRecorderLogic.outcome(keyCode: keyCode, modifiers: modifiers) {
        case .cancelled:
          recordingError = nil
          isRecording = false
        case .recorded(let shortcut):
          recordingError = nil
          isRecording = false
          onRecord(shortcut)
        case .rejected(let error):
          recordingError = error
        }
      }
      .frame(width: 1, height: 1)
      .opacity(0.01)

      if let recordingError {
        Text(recordingError.localizedDescription)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }

  private static func localized(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, bundle: .main, value: fallback, comment: "")
  }
}

private struct ShortcutCaptureView: NSViewRepresentable {
  @Binding var isRecording: Bool
  let onKey: (UInt32, ShortcutModifiers) -> Void

  func makeNSView(context: Context) -> ShortcutCaptureNSView {
    ShortcutCaptureNSView(onKey: onKey)
  }

  func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
    nsView.isRecording = isRecording
    nsView.onKey = onKey

    guard isRecording else { return }
    DispatchQueue.main.async {
      nsView.window?.makeFirstResponder(nsView)
    }
  }
}

@MainActor
private final class ShortcutCaptureNSView: NSView {
  var isRecording = false
  var onKey: (UInt32, ShortcutModifiers) -> Void

  init(onKey: @escaping (UInt32, ShortcutModifiers) -> Void) {
    self.onKey = onKey
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else {
      super.keyDown(with: event)
      return
    }

    onKey(
      UInt32(event.keyCode),
      ShortcutModifiers(modifierFlags: event.modifierFlags)
    )
  }
}

private extension ShortcutModifiers {
  init(modifierFlags: NSEvent.ModifierFlags) {
    var modifiers: ShortcutModifiers = []
    if modifierFlags.contains(.command) { modifiers.insert(.command) }
    if modifierFlags.contains(.option) { modifiers.insert(.option) }
    if modifierFlags.contains(.control) { modifiers.insert(.control) }
    if modifierFlags.contains(.shift) { modifiers.insert(.shift) }
    self = modifiers
  }
}
