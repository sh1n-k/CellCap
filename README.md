# CellCap

Apple Silicon / macOS 26+ 전용 배터리 충전 제어 앱을 목표로 하는 macOS 시스템 유틸리티 프로젝트입니다.

현재 저장소는 **정책/관측/진단 계층 위에 Helper 내부 직접 SMC 제어 backend**를 붙인 상태입니다. 외부 `batt` 같은 도구에는 의존하지 않지만, **비문서화된 저수준 AppleSMC 경로와 root 권한 helper**를 전제로 합니다.

- 공용 모델과 상태 머신
- 정책 엔진
- 배터리/전원 상태 관측
- SwiftUI 메뉴 막대 앱 골격
- XPC/Helper 통신 골격
- Helper 내부 직접 SMC read/write bridge
- 런타임 orchestration
- 진단 로그와 export 초안

개발용 기준의 privileged helper 수동 설치 스크립트와 launchd plist 템플릿은 포함되어 있습니다.
즉, **코드 차원에서는 직접 제어 backend와 개발용 설치 경로가 모두 존재하지만**, 배포형 helper 설치와 자동 승인 흐름은 아직 없습니다.

## 현재 구현 범위

- `AppUI / Core / Shared / Helper` 4개 타깃 분리
- `CellCap.xcodeproj` 생성 스크립트 유지
- `BatterySnapshot`, `ChargePolicy`, `ControllerStatus`, `AppState`, `ChargeState`
- `ChargeStateMachine`, `ChargeStateResolver`, `PolicyEngine`
- `BatteryMonitor`, `CapabilityChecker`
- `ChargeController`, `MockChargeController`, `XPCChargeController`
- `CellCapHelperXPCProtocol`, Shared DTO, Helper stub service
- `AppRuntimeOrchestrator`
- `EventLogger`, `DiagnosticsSummary`, JSON export 초안
- SwiftPM 기반 단위/통합 테스트

## 프로젝트 구조

```text
CellCap/
├── BuildSupport/
│   └── generate_xcodeproj.rb
├── CellCap.xcodeproj/
├── Package.swift
├── README.md
├── Sources/
│   ├── AppUI/
│   ├── Core/
│   ├── Helper/
│   └── Shared/
└── Tests/
    └── CoreTests/
```

## 타깃 역할

### AppUI

- SwiftUI 메뉴 막대 앱과 설정 화면
- `MenuBarViewModel`이 `AppRuntimeServicing`을 구독해 상태를 반영
- 설치/승인/업데이트 UI는 아직 미구현

### Core

- 정책 계산, 상태 전이, 배터리 관측, orchestration, 진단 로직
- UI에 의존하지 않는 순수 로직 우선
- 정책 계산, 상태 전이, 배터리 관측, orchestration, 진단 로직
- App 쪽은 `ChargeController` 추상화만 알고, 실제 제어는 Helper가 담당

### Shared

- 모델, capability 타입, XPC DTO, diagnostics 타입
- AppUI/Core/Helper 사이의 계약 계층

### Helper

- XPC helper skeleton
- `fetchControllerStatus`, `selfTest`, `capabilityProbe` 지원
- 직접 SMC 제어 backend 포함
- 실제 privileged helper 설치/승인은 아직 없음

## 개발/검증

### SwiftPM

```bash
swift build
swift test
```

### Xcode 프로젝트 재생성

```bash
ruby BuildSupport/generate_xcodeproj.rb
```

현재 이 저장소는 SwiftPM 기준 빌드/테스트를 우선 신뢰합니다.
Xcode CLI 환경이 깨져 있으면 `xcodebuild -runFirstLaunch`가 먼저 필요할 수 있습니다.

## 설치 흐름

아래는 **현재 구현 범위 기준의 설치 문서**입니다.

### 현재 가능한 설치 형태

1. 저장소를 클론합니다.
2. `swift build`를 실행해 `CellCapHelper` SwiftPM 산출물을 생성합니다.
3. 필요하면 `ruby BuildSupport/generate_xcodeproj.rb`로 앱 UI 디버깅용 Xcode 프로젝트를 생성합니다.
4. `CellCapHelper` 바이너리가 생성되었는지 확인합니다.
5. `sudo BuildSupport/dev/install_helper.sh`로 helper를 `/Library/PrivilegedHelperTools`와 `LaunchDaemons`에 설치합니다.
6. `BuildSupport/dev/helper_status.sh`로 launchd 등록 상태를 확인합니다.
7. Xcode 또는 SwiftPM으로 `CellCapApp`을 실행합니다.

### 현재 미완료 설치 항목

- 코드 서명된 배포 패키지
- `.app` 번들 내부에 helper를 포함한 설치 자동화
- `SMJobBless` 기반 설치/승인 자동화
- 로그인 자동 실행 자동 등록

### 개발용 helper 스크립트

```bash
sudo BuildSupport/dev/install_helper.sh
BuildSupport/dev/helper_status.sh
sudo BuildSupport/dev/restart_helper.sh
sudo BuildSupport/dev/uninstall_helper.sh
```

스크립트는 기본적으로 아래 경로를 사용합니다.

- helper 바이너리: `/Library/PrivilegedHelperTools/com.shin.cellcap.helper`
- launchd plist: `/Library/LaunchDaemons/com.shin.cellcap.helper.plist`
- stdout 로그: `/Library/Logs/CellCap/com.shin.cellcap.helper.stdout.log`
- stderr 로그: `/Library/Logs/CellCap/com.shin.cellcap.helper.stderr.log`

`install_helper.sh`는 먼저 SwiftPM 빌드 산출물에서 `CellCapHelper`를 찾고, 필요하면 `CELLCAP_HELPER_BINARY` 환경 변수로 직접 경로를 지정할 수 있습니다.
첫 번째 인자로 helper 바이너리 경로를 직접 넘길 수도 있습니다.

### 문서상 목표 설치 흐름

향후에는 아래 순서를 목표로 합니다.

1. 앱 번들 설치
2. 첫 실행 진단
3. privileged helper 존재/버전/권한 확인
4. 필요 시 helper 설치 및 권한 승인
5. 런타임 capability probe
6. 로그인 자동 실행 선택

현재 저장소에는 이 흐름의 **3~5단계에 필요한 진단 모델과 상태 판정만 준비**되어 있습니다.

## 첫 실행 흐름

현재 코드 기준 첫 실행 시 앱은 아래 순서로 동작합니다.

1. `CellCapApp`이 `EventLogger`, `BatteryMonitor`, `XPCChargeController`, `AppRuntimeOrchestrator`를 조립합니다.
2. `MenuBarViewModel`이 orchestration 스트림을 구독합니다.
3. `AppRuntimeOrchestrator.start()`가 초기 동기화를 시작합니다.
4. helper 설치 상태 확인
5. controller status로 XPC 연결 가능 여부 확인
6. helper가 준비된 경우에만 `selfTest`
7. 필요 시 `capabilityProbe`
8. 배터리 스냅샷 조회
9. `PolicyEngine`으로 상태 계산
10. UI 상태와 diagnostics summary 갱신

### 첫 실행에서 확인해야 할 진단 항목

- 내장 배터리 감지 여부
- Apple Silicon 여부
- macOS 26+ 여부
- helper 연결 상태
- helper 설치/launchd/XPC 상태
- capability probe 결과
- self-test 결과
- read-only / monitoring-only 전환 사유

### 현재 미완료 항목

- “첫 실행 안내 화면”
- 사용자 친화적 권한/승인 유도 UI
- helper 설치 실패 복구 화면

## helper 승인 절차

현재 저장소에는 **배포형 helper 승인 UI는 없지만**, 개발용 수동 설치 스크립트는 포함되어 있습니다.
배포형 설치를 만들기 전까지는 아래 수동 절차를 사용합니다.

### 개발용 수동 절차

1. `swift build`
2. `sudo BuildSupport/dev/install_helper.sh`
3. `BuildSupport/dev/helper_status.sh`
4. 앱 실행
5. 앱에서 `Helper 설치`, `Helper 권한`, `충전 제어` 상태 확인

### 배포형 목표 절차

1. 앱이 helper 필요 여부 판단
2. helper 버전/설치 상태 확인
3. 설치 요청
4. 관리자 승인 또는 시스템 승인 유도
5. helper 재연결 시도
6. 실패 시 `read-only fallback`

### 현재 범위에서 이미 준비된 것

- launchd 기반 개발용 설치/재시작/제거 스크립트
- helper 연결 실패 시 `ControllerStatus`에 반영
- helper 설치 상태를 `CapabilityReport`와 `DiagnosticsSummary`에 반영
- `errorReadOnly` 및 `readOnlyFallback` 상태 계산
- capability probe와 self-test 기록
- 실패 원인 diagnostics 저장

### 아직 없는 것

- `SMJobBless` 또는 동등한 privileged helper 설치 흐름
- 사용자 승인 안내 UI
- 승인 후 재시도 버튼/복구 플로우
- helper 버전 교체 로직

## 개발용 실사용 테스트 절차

아래 절차는 **배포형 검증이 아니라 단일 개발 장비에서 실제 충전 on/off가 반영되는지 보는 절차**입니다.

1. `swift build`
2. `sudo BuildSupport/dev/install_helper.sh`
3. `BuildSupport/dev/helper_status.sh`
4. `launchctl print system/com.shin.cellcap.helper`로 root launchd 상태 확인
5. 앱 실행
6. UI에서 `Helper 설치`, `Helper 권한`, `충전 제어` 항목이 모두 기대한 상태인지 확인
7. 현재 배터리보다 낮은 상한을 설정해 충전 중단 명령이 내려가는지 확인
8. 하한 이하로 내려가면 다시 충전 활성화가 내려가는지 확인
9. sleep 후 wake 하여 상태 재동기화와 helper 재조회가 일어나는지 확인
10. helper를 수동 중지한 뒤 앱이 `read-only` 또는 `errorReadOnly`로 내려가는지 확인
11. `sudo BuildSupport/dev/uninstall_helper.sh`

### 실패 시 확인 명령

```bash
BuildSupport/dev/helper_status.sh
launchctl print system/com.shin.cellcap.helper
tail -n 100 /Library/Logs/CellCap/com.shin.cellcap.helper.stdout.log
tail -n 100 /Library/Logs/CellCap/com.shin.cellcap.helper.stderr.log
```

### 예상 실패 케이스

- root 권한 없이 install 스크립트를 실행한 경우
- plist 권한이 `root:wheel 644`가 아닌 경우
- Mach service가 launchd에 bootstrap되지 않은 경우
- helper는 떠 있지만 SMC write가 실패하는 경우
- 명령 후 `isChargingEnabled` 재조회가 기대와 달라 앱이 즉시 read-only로 격하되는 경우

## 로그인 자동 실행 처리

현재 저장소에는 **로그인 자동 실행 등록 구현이 없습니다.**

### 권장 구현 방향

- `ServiceManagement` 기반 login item 등록
- 설정 UI에서 on/off 제어
- 현재 기기에서 helper 필요 여부와 분리해 관리
- 실패 시 사용자에게 “자동 실행 실패, 수동 실행 필요”를 명확히 표시

### 현재 문서상 정리만 된 상태

- 로그인 자동 실행은 App 실행 편의 기능
- helper 설치/승인과 별개로 취급
- 앱 시작 시 first-run diagnostics와 함께 상태를 다시 계산해야 함

### 실제 구현 시 점검 항목

- 로그인 직후 helper가 아직 올라오지 않았을 때의 초기 fallback
- 로그인 직후 `BatteryMonitor` 초기 이벤트 유실 방지
- 사용자가 자동 실행을 껐을 때 launch item 정리

## 업데이트 고려사항

현재 저장소에는 **자동 업데이트 및 helper 마이그레이션 구현이 없습니다.**
이 섹션은 이후 구현 시 반드시 지켜야 할 운영 규칙을 정리한 것입니다.

### 앱 업데이트 시

- AppUI/Core/Shared 버전이 함께 올라가도 XPC 계약은 하위 호환을 우선
- DTO 필드 추가는 backward-compatible 방식으로 진행
- 제거 대신 교체가 가능한 구조를 우선

### helper 업데이트 시

- helper 버전 확인 API 필요
- 앱과 helper 계약 버전 차이 감지 필요
- helper 재설치 또는 재등록 전 read-only fallback 유지 필요
- 업데이트 중 제어 불가 상태는 `errorReadOnly` 또는 `monitoringOnly`로 명확히 반영 필요

### 마이그레이션 체크리스트

- XPC protocol 변경 여부
- Shared DTO 호환성
- 기존 helper 제거/교체 순서
- launchd/ServiceManagement 재등록 필요 여부
- self-test 재실행
- capability probe 재저장

### 현재 구현 범위에서 가능한 준비

- capability probe 결과 저장
- self-test 결과 저장
- helper 통신 실패 시 read-only fallback
- helper 설치 상태와 버전 불일치 저장
- diagnostics export로 장애 보고 가능

## 제거 절차

현재 저장소에는 **제거 자동화 구현이 없습니다.**

### 수동 제거 절차

1. 앱 종료
2. 로그인 자동 실행을 구현했다면 먼저 해제
3. helper 설치 구현이 들어갔다면 helper 등록 해제
4. 앱 번들 삭제
5. 캐시/설정/진단 로그 파일 삭제

### 향후 자동 제거에서 고려할 항목

- helper 중지 및 deregistration
- launch item 해제
- diagnostics export 여부 사용자 확인
- 사용자 설정 삭제 여부 선택

### 현재 범위에서 남는 산출물

현재는 메모리 내 diagnostics만 사용하므로, 기본적으로 제거해야 할 영구 로그 파일은 없습니다.
향후 파일 저장형 export 또는 persistent log 저장이 추가되면 별도 정리 경로가 필요합니다.

## 진단/로그

현재 구현된 진단 범위:

- 정책 변경 로그
- 상태 전이 로그
- helper 통신 로그
- capability probe 저장
- self-test 저장
- diagnostics summary 생성
- JSON export 초안

진단은 디버깅용 상세 로그와 사용자용 요약을 분리합니다.
민감 정보는 저장하지 않는 방향으로 설계되어 있습니다.

## README 최종 정리

이 README는 **현재 구현 범위와 운영 절차 문서**를 함께 제공합니다.

현재 저장소가 제공하는 것은:

- 도메인 구조
- 상태 계산
- 관측 계층
- XPC/Helper skeleton
- Helper 내부 직접 SMC backend
- diagnostics

현재 저장소가 아직 제공하지 않는 것은:

- 배포형 privileged helper 설치/승인
- 로그인 자동 실행 등록
- 자동 업데이트
- 자동 제거

즉, 지금 단계의 프로젝트는 **직접 제어 backend와 개발용 수동 설치 경로는 포함하지만, 이를 제품 수준으로 배포/업데이트하는 운영 경로는 아직 미완료인 상태**입니다.

## 남은 TODO

- `SMJobBless` 또는 동등한 배포형 helper 설치/승인 구현
- launch at login 구현
- helper 버전 확인 및 마이그레이션 구현
- persistent diagnostics 저장 경로 정의
- diagnostics export UI 연결
- first-run onboarding/diagnostic 화면
- signed distribution 전략 정리
- 실제 장비에서 root helper 설치 후 end-to-end 검증
- 업데이트/제거 자동화
