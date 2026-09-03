# Fake Sleep

### 모든 디스플레이를 조용히 꺼진 것처럼 보여주는 메뉴 막대 앱

[English](README.md) · [한국어](README.ko.md) · [简体中文](README.zh-CN.md)

Fake Sleep은 연결된 디스플레이를 꺼진 것처럼 보이게 하는 네이티브 macOS 메뉴 막대 앱입니다. 논리 디스플레이마다 불투명한 검은색 오버레이를 띄우고, 복원할 때 모든 오버레이를 함께 제거합니다.

> 보이는 화면만 바꿉니다. 디스플레이 하드웨어는 건드리지 않습니다.

앱은 항상 깨어 있는 상태로 시작합니다. 실제 밝기, 모니터 전원, 백라이트 소비 전력은 변경하지 않습니다.

## 한눈에 보기

| | |
| --- | --- |
| 플랫폼 | Apple Silicon Mac · macOS 13 Ventura 이상 |
| 인터페이스 | 메뉴 막대 전용 — Dock 아이콘 없음 |
| 기본 단축키 | Option-Command-S (`⌥⌘S`) |
| 복구 | 설정한 단축키와 활성 상태의 Escape |
| 기술 스택 | AppKit, SwiftUI, Carbon, 공개 macOS API |

## 주요 기능

- 연결된 모든 디스플레이를 불투명한 검은색 창으로 덮습니다.
- 설정한 전역 단축키 또는 긴급 Escape로 모든 디스플레이를 함께 복원합니다.
- 활성 상태에서 디스플레이 연결/분리, 배열, 해상도, 깨우기, Spaces 변경을 추적합니다.
- 논리 디스플레이마다 오버레이 하나를 유지하고 중복 없이 구성을 조정합니다.
- 단축키 녹화, 기본값 재설정, 선택적 로그인 시 실행을 제공합니다.
- 영어와 한국어 UI를 제공합니다.

## 빠른 시작

이 저장소는 소스 코드만 제공합니다. Xcode에서 앱을 빌드하고 실행하세요.

1. `FakeSleep.xcodeproj`를 엽니다.
2. `FakeSleep` 스킴과 실행 대상으로 **My Mac**을 선택합니다.
3. **Product → Run**으로 실행합니다.
4. 메뉴 막대의 달 아이콘에서 Fake Sleep을 시작하거나 복원합니다.

## 소스에서 빌드하기

### 요구사항

- Apple Silicon Mac (`arm64`)
- macOS 13 Ventura 이상
- macOS 플랫폼이 설치된 Xcode

### Xcode

`FakeSleep.xcodeproj`를 열고 `FakeSleep` 스킴을 선택한 뒤 **My Mac**으로 빌드합니다. 프로젝트는 Swift 6, App Sandbox, Hardened Runtime 설정을 사용합니다.

### 명령줄

전체 XCTest를 실행합니다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project FakeSleep.xcodeproj \
  -scheme FakeSleep \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test
```

서명 없이 Release 앱을 빌드합니다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project FakeSleep.xcodeproj \
  -scheme FakeSleep \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

빌드 결과물은 Xcode의 DerivedData 디렉터리에 생성됩니다. 공증된 배포 패키지나 App Store 제출용 파일은 생성하지 않습니다.

## 사용법

### 메뉴 막대

Dock 아이콘 없이 메뉴 막대에서 동작합니다. **Start Fake Sleep**은 화면을 덮고, **Restore Displays**는 오버레이를 제거합니다. **Settings…**에서 설정을 열고 **Quit Fake Sleep**으로 종료합니다.

### 단축키

기본 전역 단축키는 `⌥⌘S`입니다. **Settings…**에서 다른 조합을 녹화할 수 있습니다. 단축키에는 일반 키 하나와 Command, Option, Control 중 하나 이상이 필요합니다. Shift는 함께 사용할 수 있지만 단독으로 사용할 수 없습니다.

Escape는 단축키 녹화를 취소합니다. Fake Sleep이 활성화된 동안에는 긴급 복구 키로 동작합니다. 다른 앱이 단축키를 사용 중이면 이전에 동작하던 단축키를 유지하고 충돌을 설정 화면에 표시합니다.

## 로그인 시 실행

로그인 시 실행은 기본적으로 꺼져 있으며 `SMAppService.mainApp`을 통해 macOS 로그인 항목에 등록됩니다.

macOS에 **승인 필요**가 표시되면 Fake Sleep 설정에서 **Open Login Items Settings**를 선택하고 시스템 설정에서 앱을 승인하세요. macOS가 실제로 활성 상태를 보고한 뒤에만 **Enabled**로 표시됩니다. 설정 창을 다시 열거나 앱으로 돌아오면 상태가 갱신됩니다.

## 여러 디스플레이와 Spaces

각 논리 디스플레이에 메뉴 막대와 Dock 영역을 포함한 정확한 화면 프레임 크기의 오버레이를 적용합니다. 오버레이는 모든 Spaces에 참여하고 고정된 상태로 유지되며 전체 화면 앱과 함께 동작합니다.

활성 상태에서 디스플레이 연결/분리, 해상도, 회전, 배열, 깨우기 알림이 발생하면 오버레이 구성을 다시 조정합니다. 제거된 디스플레이의 오버레이는 닫고 새 디스플레이에는 오버레이 하나를 추가합니다.

## 개인정보와 한계

네트워크, 텔레메트리, 화면 캡처, Apple Events, 손쉬운 사용 권한, 사용자 데이터 수집을 사용하지 않습니다. 화면 내용을 읽지 않으며 저장하는 설정은 선택한 단축키뿐입니다.

효과는 시각적인 것뿐입니다. 검은색 소프트웨어 오버레이를 사용할 뿐 실제 밝기, DDC/CI, 모니터 전원, 에너지 소비를 변경하지 않습니다.

## 문제 해결

### 단축키를 사용할 수 없음

다른 앱이 이미 해당 조합을 사용하고 있을 수 있습니다. 설정에서 다른 단축키를 선택하세요. 새 등록에 실패하면 마지막으로 유효했던 단축키를 유지합니다. 복구가 가능한 상태라면 메뉴 막대 항목이나 Escape를 사용할 수 있습니다.

### 로그인 시 실행이 계속 대기 중임

**Open Login Items Settings**를 선택하고 Fake Sleep을 승인한 다음 앱으로 돌아오세요. 설정 창을 열거나 앱이 활성화될 때 표시 상태가 갱신됩니다.

### 활성 상태에서 디스플레이가 바뀜

macOS가 디스플레이 구성 변경 알림을 보내면 오버레이를 다시 조정합니다. 화면이 계속 가려지지 않으면 먼저 복원하고 macOS가 디스플레이를 인식하는지 확인한 뒤 다시 활성화하세요.

## App Store 준비

배포 전에 예시 번들 식별자 `com.example.FakeSleep`를 서명 팀이 소유한 식별자로 바꾸고, Xcode에서 올바른 개발 팀과 서명/프로비저닝을 설정하세요.

App Store 아카이브 서명, 공증, App Store Connect 메타데이터, 인증서, 스크린샷, 실제 제출은 이 소스 저장소의 범위에 포함되지 않습니다.
