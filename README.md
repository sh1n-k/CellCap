# CellCap

CellCap은 **Apple Silicon / macOS 26+** 환경에서 배터리 충전 상태를 관측하고,
조건이 맞으면 **충전 제한(control)** 을 시도하는 macOS 메뉴 막대 유틸리티입니다.

현재는 **개발용 프로토타입** 단계입니다.
앱 본체와 privileged helper가 분리되어 있고, 충전 제어는 Helper 내부의 **비문서화된 경로**를 사용합니다.
SMC 충전 키가 있는 펌웨어는 직접 AppleSMC backend를, 키가 제거된 펌웨어(macOS 26.7 이후 등)는 macOS 충전 한도 설정 backend를 씁니다. 자세한 동작은 `docs/adr/0002-charge-limit-backend.md`를 참고하세요.

## 한눈에 보기
- 메뉴 막대 UI로 현재 배터리 상태와 제어 상태를 확인할 수 있습니다.
- 충전 상한, 재충전 하한, 임시 100% 충전을 설정할 수 있습니다.
- Helper 연결 실패나 권한 문제 시 자동으로 `read-only` 또는 `monitoring-only`로 안전하게 내려갑니다.
- 진단 로그와 diagnostics export 초안이 포함되어 있습니다.

## 현재 상태
### 되는 것
- SwiftUI 메뉴 막대 앱
- 배터리/전원 상태 관측
- 정책 기반 상태 계산
- XPC 기반 Helper 통신
- 앱 설정(고급 정보)에서 helper 설치/승인 안내/제거 (SMAppService)
- 단위 테스트와 CI

### 아직 안 되는 것
- 일반 사용자를 위한 설치 패키지
- Developer ID 서명/공증 (현재는 자체 서명 인증서)
- 자동 업데이트
- 제품 수준 복구 UI

즉, **직접 실행해 실험하고 개발하기에는 가능하지만, 일반 사용자용 배포 상태는 아닙니다.**

## 지원 환경
- Apple Silicon Mac
- macOS 26 이상
- 시스템 설정에서 백그라운드 helper 실행을 허용할 수 있는 환경
- 코드 서명 인증서 `CellCap Dev` (키체인 접근 > 인증서 지원 > 인증서 생성, 자체 서명 루트, 코드 서명)

지원 환경이 아니거나 Helper가 준비되지 않으면 앱은 충전 제어를 강행하지 않고 관측 모드로 동작합니다.

## 빠른 시작
### 1. 빌드

```bash
swift build
```

### 2. 앱 번들 빌드와 설치

```bash
BuildSupport/dev/build_install_app.sh
```

helper를 포함한 `CellCap.app`을 `CellCap Dev` 인증서로 서명해 `/Applications`에 설치하고 실행합니다.
소스 파일을 추가/삭제했다면 먼저 `ruby BuildSupport/generate_xcodeproj.rb`로 Xcode 프로젝트를 다시 생성합니다.

### 3. helper 설치
1. 메뉴 막대의 CellCap > 고급 정보에서 `Helper 설치`를 누릅니다.
2. 시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램 > 백그라운드에서 허용에서 CellCap을 켭니다.
3. 고급 정보의 설치 상태가 `XPC 연결 확인`으로 바뀌는지 확인합니다.

helper 바이너리가 바뀐 빌드를 설치하면 고급 정보에 `버전 불일치` 또는 `시스템 승인 필요`가 표시됩니다.
`다시 설치`를 누르고 시스템 설정에서 CellCap을 다시 허용합니다(자체 서명은 바이너리가 바뀔 때마다 재승인이 필요).
`swift run CellCapApp`처럼 앱 번들 밖에서 실행하면 helper를 설치하거나 연결할 수 없습니다.

### 4. 앱에서 확인할 것
- `Helper 설치`
- `Helper 권한`
- `충전 제어`
- 현재 배터리 상태와 정책 상태

## 개발용 helper 스크립트
```bash
BuildSupport/dev/build_install_app.sh      # 앱(helper 포함) 빌드·서명·설치
BuildSupport/dev/helper_status.sh          # launchd/백그라운드 항목 상태
sudo BuildSupport/dev/uninstall_helper.sh  # 이전 방식 설치 제거 또는 helper 강제 중지 + 충전 한도 복원
```

helper 위치:
- 실행 파일: `/Applications/CellCap.app/Contents/MacOS/CellCapHelper`
- LaunchDaemon plist: `/Applications/CellCap.app/Contents/Library/LaunchDaemons/com.shin.cellcap.helper.plist`
- 로그: `/usr/bin/log show --last 10m --predicate 'process == "CellCapHelper"'`

이전 방식(`/Library/PrivilegedHelperTools`) 설치가 남아 있으면 앱이 `이전 설치 남음`으로 표시하고 설치를 막습니다.
`sudo BuildSupport/dev/uninstall_helper.sh`로 지운 뒤 새로고침합니다.

## 검증
기본 검증 명령:

```bash
swift build
swift test
```

GitHub Actions에서도 같은 범위의 검증을 수행합니다.
root 권한이 필요한 helper 실기기 점검은 CI에 포함하지 않습니다.

## 문제 확인
Helper 상태나 launchd 등록이 의심되면 아래 명령을 먼저 확인합니다.

```bash
BuildSupport/dev/helper_status.sh
sudo launchctl print system/com.shin.cellcap.helper
/usr/bin/log show --last 10m --style compact | grep -i cellcap.helper
```

`Launch Constraint Violation`이나 `OS_REASON_CODESIGNING`이 보이면 서명이 바뀐 helper입니다. 고급 정보에서 `다시 설치` 후 시스템 설정에서 다시 허용합니다.
`Disallowing com.shin.cellcap.helper because no eligible provisioning profiles found` 로그는 helper에 entitlement가 없어 생기는 무해한 로그입니다.

실기기 점검에서는 아래 흐름을 우선 봅니다.
- helper가 정상 설치되고 launchd에 등록되는지
- 앱이 helper 설치/권한/제어 가능 여부를 올바르게 보여주는지
- 상한/하한 정책에 따라 충전 중단과 재개가 기대대로 반영되는지
- sleep/wake 뒤 재동기화가 되는지
- helper 중지 또는 연결 실패 시 안전하게 fallback 되는지

## 프로젝트 구조
```text
Sources/AppUI     SwiftUI 화면과 표시용 상태 해석
Sources/Core      정책 계산, 런타임 동기화, 진단, 관측, XPC 클라이언트
Sources/Shared    AppUI/Core/Helper 공용 계약과 모델
Sources/Helper    privileged helper와 충전 제어 backend(SMC / macOS 충전 한도)
BuildSupport/dev  앱 빌드·설치, helper 상태/제거 스크립트, 앱 번들 내장 LaunchDaemon plist
Tests/CoreTests   Core/Helper 회귀 테스트
Tests/AppUITests  AppUI 순수 로직 테스트
```

## 추가 문서
- 개발/유지보수 규칙: [AGENTS.md](./AGENTS.md)
- 런타임/Helper 경계 결정: [docs/adr/0001-runtime-and-helper-boundaries.md](./docs/adr/0001-runtime-and-helper-boundaries.md)
- 앱 내장 helper 설치(SMAppService): [docs/adr/0003-in-app-helper-installation.md](./docs/adr/0003-in-app-helper-installation.md)
