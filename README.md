# Fake Sleep

## Product summary

Fake Sleep is a native, menu-bar-only macOS utility for making connected displays look switched off. When activated, it places an opaque black software overlay over every logical display. The configured shortcut or Escape restores the displays immediately.

The app always starts awake and never changes the physical state of a display. It does not dim the backlight or reduce power consumption.

## Features

- Covers every connected display with a black overlay.
- Restores all displays with the same global shortcut or emergency Escape.
- Supports display connection, disconnection, arrangement, resolution, wake, and Space changes while active.
- Provides a configurable global shortcut, defaulting to Option-Command-S (`⌥⌘S`).
- Includes a menu-bar status item with Settings and Quit actions.
- Offers optional Launch at Login through macOS Login Items.
- Includes English and Korean UI localization.

## Requirements

- Apple Silicon Mac (arm64).
- macOS 13 Ventura or later.
- Full Xcode for building the project.

## Build instructions

Open `FakeSleep.xcodeproj` in Xcode, select the `FakeSleep` scheme, and build for **My Mac**.

The equivalent command-line test build is:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project FakeSleep.xcodeproj \
  -scheme FakeSleep \
  -destination 'platform=macOS,arch=arm64' test
```

For a Release build without a signing identity:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project FakeSleep.xcodeproj \
  -scheme FakeSleep \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

## Usage

Fake Sleep runs in the menu bar and does not add a Dock icon. Choose **Start Fake Sleep** to cover the displays, or **Restore Displays** to remove the overlays.

The default global shortcut is `⌥⌘S`. Open **Settings…** to record a different shortcut. The shortcut must contain one non-modifier key and at least Command, Option, or Control. Escape cancels shortcut recording and is reserved as the emergency restore key while Fake Sleep is active.

## Launch at Login

Launch at Login is off by default. Enabling it registers Fake Sleep with the macOS Login Items service. macOS may report **Approval Required** until the user approves the app.

If approval is required, open the Login Items settings from the Fake Sleep Settings window and enable Fake Sleep under **Allow in the Background** or the applicable Login Items section. The toggle only reports enabled after macOS reports the service as enabled.

## Multi-display and Spaces behavior

Fake Sleep covers each logical display using its exact screen frame, including the menu bar and Dock regions. Overlays join all Spaces and remain stationary and auxiliary to full-screen applications. Connecting or disconnecting displays, changing their arrangement or resolution, and waking the Mac triggers reconciliation while Fake Sleep is active.

## Privacy

Fake Sleep has no network, telemetry, screen-capture, Apple Events, accessibility, or user-data collection feature. It uses public macOS APIs and stores only the selected shortcut in the app's standard preferences. No display image or screen content is read.

## Limitation

Fake Sleep uses black software overlays only. It does not change physical brightness, use DDC/CI, control monitor power, or promise energy savings. The display backlight and other hardware remain under macOS and monitor control.

## Troubleshooting

### Shortcut conflicts

If another application owns the selected shortcut, Fake Sleep keeps the previous working shortcut and shows an inline registration error. Choose another combination in Settings or use the menu bar item. Escape remains available for emergency restoration while Fake Sleep is active when its registration succeeded.

### Login Items approval

If Launch at Login remains in **Approval Required**, use **Open Login Items Settings**, approve Fake Sleep in System Settings, then return to the app. Reopening Settings or bringing the app to the foreground refreshes the reported status.

### Display hot-plug behavior

When a display is connected or removed while active, Fake Sleep rebuilds the overlay set on the next display-configuration notification. If a display remains uncovered after a hardware or arrangement change, restore first, confirm the display is available to macOS, and activate Fake Sleep again.

## App Store preparation

Before distribution, replace the example bundle identifier `com.example.FakeSleep` with the identifier owned by the App Store team, select the correct signing team, and configure the required signing and provisioning settings in Xcode. App Store archive signing, notarization, App Store Connect metadata, screenshots, certificates, and publication are not included in this repository.
