# Fake Sleep

### A quiet, software-only blackout for every display.

[English](README.md) · [한국어](README.ko.md) · [简体中文](README.zh-CN.md)

Fake Sleep is a native, menu-bar-only macOS utility that makes connected displays look switched off. It places an opaque black overlay over every logical display, then removes every overlay when you restore it.

> It changes what you see, not what your display does.

The app always starts awake. It does not change physical brightness, monitor power, or backlight consumption.

## At a glance

| | |
| --- | --- |
| Platform | Apple Silicon Mac · macOS 13 Ventura or later |
| Interface | Menu bar only — no Dock icon |
| Default shortcut | Option-Command-S (`⌥⌘S`) |
| Recovery | The configured shortcut, plus Escape while active |
| Stack | AppKit, SwiftUI, Carbon, and public macOS APIs |

## What it does

- Covers every connected display with an opaque black window.
- Restores all displays together from the configured global shortcut or emergency Escape.
- Tracks display connection, removal, arrangement, resolution, wake, and Space changes while active.
- Keeps one overlay per logical display and reconciles the set without duplicates.
- Provides shortcut recording, reset-to-default, and optional Launch at Login settings.
- Ships with English and Korean UI localization.

## Quick start

This repository is source-only. Build and run the app from Xcode:

1. Open `FakeSleep.xcodeproj`.
2. Select the `FakeSleep` scheme and **My Mac** as the destination.
3. Run with **Product → Run**.
4. Use the moon icon in the menu bar to start or restore Fake Sleep.

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

Fake Sleep has no Dock icon. Select **Start Fake Sleep** to cover the displays, **Restore Displays** to remove the overlays, **Settings…** to configure the app, or **Quit Fake Sleep** to exit.

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

Fake Sleep uses no network, telemetry, screen capture, Apple Events, Accessibility permission, or user-data collection. It does not read screen contents. The only saved preference is the selected shortcut.

The effect is visual only: Fake Sleep uses black software overlays and does not change physical brightness, use DDC/CI, control monitor power, or reduce energy consumption.

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
