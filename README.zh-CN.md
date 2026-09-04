# Fake Sleep

### 离开座位时，让 Mac 继续工作

[English](README.md) · [한국어](README.ko.md) · [简体中文](README.zh-CN.md)

Fake Sleep 是一款帮助你离开座位时保持工作的原生 macOS 菜单栏工具。默认的 **安全离开** 模式只会阻止系统因闲置而睡眠，因此下载、构建和 AI 任务可以继续。离开前请自行按下 `⌃⌘Q` 锁定 macOS；Fake Sleep 不会代替你声称 Mac 已锁定。

可选的 **仅隐藏屏幕** 模式会在每个逻辑显示器上放置不透明的黑色覆盖层。它只是视觉隐私辅助，不是安全功能。

显示器睡眠时间仍遵循 macOS 设置。应用不会改变实际亮度、显示器电源或背光功耗。

## 快速了解

| | |
| --- | --- |
| 平台 | Apple Silicon Mac · macOS 13 Ventura 或更高版本 |
| 界面 | 仅菜单栏 — 不显示 Dock 图标 |
| 默认快捷键 | Option-Command-S (`⌥⌘S`) |
| 默认会话 | 直到你停止 |
| 电池保护 | 电量 10% 时自动停止（可配置） |
| 恢复方式 | 已配置的快捷键，以及激活期间的 Escape |
| 技术栈 | AppKit、SwiftUI、Carbon 和公开的 macOS API |

## 主要功能

- 活跃会话期间阻止系统因闲置而睡眠，同时允许显示器睡眠。
- 在推荐模式中指导你使用 `⌃⌘Q` 锁定 macOS。
- 在仅隐藏屏幕模式中用不透明的黑色窗口覆盖所有已连接的显示器。
- 使用已配置的全局快捷键或紧急 Escape 一起恢复所有显示器。
- 在激活期间跟踪显示器连接、移除、排列、分辨率、唤醒和 Space 变化。
- 为每个逻辑显示器保持一个覆盖窗口，并在调整时避免重复创建。
- 提供快捷键录制、恢复默认值和可选的登录时启动设置。
- 提供可选择模式、时间、电池、快捷键和登录时启动的三步引导。
- 提供英文、韩文、日文和简体中文界面本地化。

## 快速开始

本仓库只包含源代码。请使用 Xcode 构建并运行应用：

1. 打开 `FakeSleep.xcodeproj`。
2. 选择 `FakeSleep` scheme，并将 **My Mac** 设为运行目标。
3. 使用 **Product → Run** 运行。
4. 完成引导；推荐的默认模式是 **安全离开**。
5. 通过菜单栏中的月亮图标启动或恢复会话。

## 从源代码构建

### 环境要求

- Apple Silicon Mac（`arm64`）。
- macOS 13 Ventura 或更高版本。
- 已安装 macOS 平台的 Xcode。

### Xcode

打开 `FakeSleep.xcodeproj`，选择 `FakeSleep` scheme，并为 **My Mac** 构建。项目使用 Swift 6、App Sandbox 和 Hardened Runtime 设置。

### 命令行

运行完整 XCTest 测试套件：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project FakeSleep.xcodeproj \
  -scheme FakeSleep \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test
```

在没有签名身份的情况下构建 Release 应用：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project FakeSleep.xcodeproj \
  -scheme FakeSleep \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

构建结果会放在 Xcode 的 DerivedData 目录中。上述命令不会生成经过公证或可直接提交 App Store 的发行包。

## 使用方法

### 菜单栏

Fake Sleep 不会显示 Dock 图标。选择 **安全离开** 来阻止系统闲置睡眠，或选择 **仅隐藏屏幕** 使用视觉黑屏。选择 **结束会话** 或已配置的恢复快捷键来停止活跃会话。**设置…** 会修改下一次会话的默认值，**使用方法** 可随时重新打开引导。

### 模式与 macOS 锁定

**安全离开** 是推荐模式。Fake Sleep 开始阻止闲置睡眠后，会提示你按下 `⌃⌘Q`。会话由 macOS 账户认证保护，而不是 Fake Sleep。若在 60 秒提示时间内没有锁定 macOS，会话将结束。

**仅隐藏屏幕** 不会锁定 Mac。任何可以操作 Mac 的人都能恢复显示器，因此请勿将此模式作为安全边界。

两种模式下，显示器睡眠时间都由 **系统设置 → 锁定屏幕** 控制。应用不会禁用显示器睡眠。

### 会话时间与电池保护

可选择 **30 分钟**、**1 小时**、**2 小时**、**4 小时** 或 **直到你停止**。使用电池时，默认在 10% 自动停止；可在设置中选择 0–100%。设为 0% 可关闭电池自动停止。连接电源适配器时不应用此阈值。

### 快捷键

默认全局快捷键为 `⌥⌘S`。打开 **Settings…** 可以录制新的组合。快捷键必须包含一个非修饰键，以及 Command、Option 或 Control 中至少一个；可以添加 Shift，但不能只使用 Shift。

Escape 会取消快捷键录制。Fake Sleep 激活时，Escape 是紧急恢复键。如果所选快捷键已被其他应用占用，Fake Sleep 会保留上一个可用快捷键，并在设置界面内显示冲突。

## 登录时启动

登录时启动默认关闭，并通过 `SMAppService.mainApp` 使用 macOS 登录项服务。

如果 macOS 显示 **Approval Required**，请在 Fake Sleep 设置中选择 **Open Login Items Settings**，然后在系统设置中批准该应用。只有 macOS 报告服务已启用后，Fake Sleep 才会显示 **Enabled**。重新打开设置或回到应用后，状态会刷新。

## 多显示器与 Spaces

每个逻辑显示器都会获得一个覆盖其精确屏幕范围的窗口，包括菜单栏和 Dock 区域。覆盖窗口会加入所有 Spaces，保持固定，并与全屏应用协同工作。

在激活期间，显示器热插拔、分辨率、旋转、排列或唤醒通知都会触发重新调整。被移除显示器的覆盖窗口会关闭，新显示器会获得一个覆盖窗口。

## 隐私与限制

Fake Sleep 不使用网络、遥测、屏幕录制、Apple Events、辅助功能权限，也不收集用户数据。它不会读取屏幕内容；保存的偏好包括模式、会话时长、电池阈值、引导版本、登录时启动和快捷键。

闲置睡眠保护只适用于普通的系统闲置睡眠。Fake Sleep 无法阻止合上 MacBook 屏幕、用户发起或强制睡眠、关机或温度保护。仅隐藏屏幕模式不提供账户安全。除此之外，效果仅通过软件覆盖实现，不会改变实际亮度、使用 DDC/CI、控制显示器电源，也不保证降低能耗。

## 问题排查

### 快捷键不可用

其他应用可能已经占用了该组合。请在设置中选择新的快捷键。如果新快捷键注册失败，Fake Sleep 会保留上一个有效快捷键。可用时，也可以使用菜单栏项目或 Escape 进行恢复。

### 登录时启动一直处于待批准状态

选择 **Open Login Items Settings**，批准 Fake Sleep，然后回到应用。打开设置或应用重新激活时，显示状态会刷新。

### Fake Sleep 激活时显示器发生变化

macOS 发布显示器配置变更通知后，Fake Sleep 会重新调整覆盖窗口。如果某块显示器仍未被覆盖，请先恢复，确认 macOS 能看到该显示器，再次激活 Fake Sleep。

## App Store 准备

正式分发前，请将示例 bundle identifier `com.example.FakeSleep` 替换为签名团队拥有的标识符，并在 Xcode 中选择正确的开发团队、配置签名和 provisioning。

App Store 归档签名、公证、App Store Connect 元数据、证书、截图及实际发布不在本源代码仓库的范围内。
