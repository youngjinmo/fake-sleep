# Fake Sleep

### Keep your Mac working while you step away.

[English](README.md) · [한국어](README.ko.md) · [简体中文](README.zh-CN.md)

Fake Sleep is a native, menu-bar-only macOS utility for unattended work. Its default **Safely Leave** mode prevents idle system sleep so downloads, builds, and AI tasks can continue. Before you leave, press `⌃⌘Q` yourself to lock macOS; Fake Sleep never pretends to have locked the Mac for you.

The optional **Hide the screen only** mode places an opaque black overlay over every logical display. It is a visual privacy aid, not a security feature.

Display sleep still follows your macOS settings. Fake Sleep does not change physical brightness, monitor power, or backlight consumption.

## At a glance

| | |
| --- | --- |
| Platform | Apple Silicon Mac · macOS 13 Ventura or later |
| Interface | Menu bar only — no Dock icon |
| Default shortcut | Option-Command-S (`⌥⌘S`) |
| Default session | Until you stop it |
| Battery protection | Auto-stop at 10% on battery (configurable) |
| Recovery | The configured shortcut, plus Escape while active |
| Stack | AppKit, SwiftUI, Carbon, and public macOS APIs |

## What it does

- Prevents idle system sleep during an active session while allowing display sleep.
- Guides you through locking macOS with `⌃⌘Q` in the recommended mode.
- Covers every connected display with an opaque black window in the visual-only mode.
- Restores all displays together from the configured global shortcut or emergency Escape.
- Tracks display connection, removal, arrangement, resolution, wake, and Space changes while active.
- Keeps one overlay per logical display and reconciles the set without duplicates.
- Provides shortcut recording, reset-to-default, and optional Launch at Login settings.
- Provides a three-step onboarding flow with mode, duration, battery, shortcut, and login-at-launch choices.
- Ships with English, Korean, Japanese, and Simplified Chinese UI localization.

## Quick start

This repository is source-only. Build and run the app from Xcode:

1. Open `FakeSleep.xcodeproj`.
2. Select the `FakeSleep` scheme and **My Mac** as the destination.
3. Run with **Product → Run**.
4. Complete onboarding. The recommended default is **Safely Leave**.
5. Use the moon icon in the menu bar to start or restore a session.

## Build from source

### Requirements

- Apple Silicon Mac (`arm64`).
- macOS 13 Ventura or later.
- Xcode with the macOS platform installed.

### Xcode

Open `FakeSleep.xcodeproj`, choose the `FakeSleep` scheme, and build for **My Mac**. The project uses Swift 6, App Sandbox, and Hardened Runtime settings.

### Command line

Run the complete XCTest suite:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project FakeSleep.xcodeproj \
  -scheme FakeSleep \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test
```

Build a Release app without a signing identity:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project FakeSleep.xcodeproj \
  -scheme FakeSleep \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

The commands create a local build product in Xcode’s DerivedData directory. They do not produce a notarized or App Store-ready distribution package.

## How to use it

### Menu bar

Fake Sleep has no Dock icon. Choose **Safely Leave** to prevent idle system sleep, or **Hide the screen only** for a visual blackout. Choose **End Session** or the configured restore shortcut to stop an active session. **Settings…** changes defaults for the next session, and **Show User Guide** reopens onboarding at any time.

### Modes and macOS lock

**Safely Leave** is the recommended mode. Fake Sleep starts idle-sleep prevention and waits for you to press `⌃⌘Q`. macOS account authentication—not Fake Sleep—protects the session. If you do not lock macOS within the 60-second prompt, the session ends.

**Hide the screen only** covers the displays but does not lock the Mac. Anyone who can interact with the Mac may restore the display, so never use this mode as a security boundary.

Display sleep timing is controlled by **System Settings → Lock Screen** in both modes. The app does not disable display sleep.

### Session time and battery protection

Choose one of **30 minutes**, **1 hour**, **2 hours**, **4 hours**, or **Until you stop it**. On battery power, the default auto-stop threshold is 10%; set it from 0–100% in Settings. Set it to 0% to turn battery auto-stop off. The threshold does not apply while a power adapter is connected.

### Shortcuts

The default global shortcut is `⌥⌘S`. Open **Settings…** to record another combination. A shortcut must contain one non-modifier key and at least Command, Option, or Control; Shift can be added but cannot be the only modifier.

Escape cancels shortcut recording. While Fake Sleep is active, Escape is the emergency restore key. If another application owns the selected shortcut, Fake Sleep keeps the previous working shortcut and reports the conflict inline.

## Launch at Login

Launch at Login is off by default and uses macOS Login Items through `SMAppService.mainApp`.

If macOS shows **Approval Required**, choose **Open Login Items Settings** in Fake Sleep Settings and approve the app in System Settings. Fake Sleep reports **Enabled** only after macOS reports the service as enabled. Reopening Settings or returning to the app refreshes the status.

## Multi-display and Spaces

Each logical display receives an overlay sized to its exact screen frame, including the menu bar and Dock regions. Overlays join all Spaces, remain stationary, and cooperate with full-screen applications.

Display hot-plug, resolution, rotation, arrangement, and wake notifications trigger reconciliation while Fake Sleep is active. A removed display’s overlay is closed; a new display receives one overlay.

## Privacy and limitations

Fake Sleep uses no network, telemetry, screen capture, Apple Events, Accessibility permission, or user-data collection. It does not read screen contents. Preferences include the selected mode, session duration, battery threshold, onboarding version, login-at-launch choice, and shortcut.

Idle-sleep prevention is scoped to normal idle sleep. Fake Sleep cannot prevent a MacBook lid from being closed, a user-initiated or forced sleep, shutdown, or thermal protection. The visual-only mode provides no account security. The effect is otherwise software-only: Fake Sleep does not change physical brightness, use DDC/CI, control monitor power, or claim to reduce energy consumption.

## Troubleshooting

### A shortcut is unavailable

Another app may already own the combination. Open Settings and choose a different shortcut. Your last valid shortcut remains active when a new registration fails. Use the menu bar item or Escape for restoration when available.

### Launch at Login remains pending

Open **Open Login Items Settings**, approve Fake Sleep, and return to the app. The displayed state is refreshed when Settings opens and when the app becomes active.

### A display changes while Fake Sleep is active

Fake Sleep reconciles overlays after macOS posts a display-configuration notification. If a display remains uncovered, restore first, confirm that macOS sees the display, and activate Fake Sleep again.

## App Store preparation

Before distribution, replace the example bundle identifier `com.example.FakeSleep` with an identifier owned by the signing team, select the correct development team, and configure signing and provisioning in Xcode.

App Store archive signing, notarization, App Store Connect metadata, certificates, screenshots, and publication are outside the scope of this source repository.
