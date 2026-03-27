# CellCap

CellCap은 **Apple Silicon / macOS 26+** 환경에서 배터리 충전 상태를 관측하고,
조건이 맞으면 **충전 제한(control)** 을 시도하는 macOS 메뉴 막대 유틸리티입니다.

현재는 **개발용 프로토타입** 단계입니다.
앱 본체와 privileged helper가 분리되어 있고, 직접 충전 제어는 Helper 내부의 **비문서화된 AppleSMC backend**를 전제로 합니다.

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
- 개발용 helper 설치/재시작/제거 스크립트
- 단위 테스트와 CI

### 아직 안 되는 것
- 일반 사용자를 위한 설치 패키지
- 자동 helper 설치/승인
- 로그인 자동 실행
- 자동 업데이트
- 제품 수준 복구 UI

즉, **직접 실행해 실험하고 개발하기에는 가능하지만, 일반 사용자용 배포 상태는 아닙니다.**

## 지원 환경
- Apple Silicon Mac
- macOS 26 이상
- root 권한으로 실행되는 privileged helper를 허용할 수 있는 개발 환경

지원 환경이 아니거나 Helper가 준비되지 않으면 앱은 충전 제어를 강행하지 않고 관측 모드로 동작합니다.

## 빠른 시작
### 1. 빌드

```bash
swift build
```

### 2. 개발용 helper 설치

```bash
sudo BuildSupport/dev/install_helper.sh
BuildSupport/dev/helper_status.sh
```

### 3. 앱 실행
- Xcode에서 `CellCapApp` 실행
- 또는 필요 시 Xcode 프로젝트 생성:

```bash
ruby BuildSupport/generate_xcodeproj.rb
```

### 4. 앱에서 확인할 것
- `Helper 설치`
- `Helper 권한`
- `충전 제어`
- 현재 배터리 상태와 정책 상태

## 개발용 helper 스크립트
```bash
sudo BuildSupport/dev/install_helper.sh
BuildSupport/dev/helper_status.sh
sudo BuildSupport/dev/restart_helper.sh
sudo BuildSupport/dev/uninstall_helper.sh
```

기본 경로:
- helper 바이너리: `/Library/PrivilegedHelperTools/com.shin.cellcap.helper`
- launchd plist: `/Library/LaunchDaemons/com.shin.cellcap.helper.plist`
- stdout 로그: `/Library/Logs/CellCap/com.shin.cellcap.helper.stdout.log`
- stderr 로그: `/Library/Logs/CellCap/com.shin.cellcap.helper.stderr.log`

`install_helper.sh`는 SwiftPM 산출물의 `CellCapHelper`를 우선 찾습니다.
필요하면 `CELLCAP_HELPER_BINARY` 환경 변수나 첫 번째 인자로 경로를 직접 넘길 수 있습니다.

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
launchctl print system/com.shin.cellcap.helper
tail -n 100 /Library/Logs/CellCap/com.shin.cellcap.helper.stdout.log
tail -n 100 /Library/Logs/CellCap/com.shin.cellcap.helper.stderr.log
```

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
Sources/Helper    privileged helper와 직접 SMC backend
BuildSupport/dev  helper 설치/상태/재시작/제거 스크립트
Tests/CoreTests   Core/Helper 회귀 테스트
Tests/AppUITests  AppUI 순수 로직 테스트
```

## 추가 문서
- 개발/유지보수 규칙: [AGENTS.md](./AGENTS.md)
- 런타임/Helper 경계 결정: [docs/adr/0001-runtime-and-helper-boundaries.md](./docs/adr/0001-runtime-and-helper-boundaries.md)
- 공개 API 검토 메모: [03_공개API_충전제어_검토.md](./03_%EA%B3%B5%EA%B0%9CAPI_%EC%B6%A9%EC%A0%84%EC%A0%9C%EC%96%B4_%EA%B2%80%ED%86%A0.md)
