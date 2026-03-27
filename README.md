# CellCap

Apple Silicon / macOS 26+ 전용 배터리 충전 제어 앱을 목표로 하는 macOS 시스템 유틸리티 프로젝트입니다.

현재 저장소는 **실제 저수준 충전 제어를 완료한 상태가 아니라**, 아래 범위를 구현한 **구조화된 골격 + 정책/관측/진단 계층**까지를 포함합니다.

- 공용 모델과 상태 머신
- 정책 엔진
- 배터리/전원 상태 관측
- SwiftUI 메뉴 막대 앱 골격
- XPC/Helper 통신 골격
- 런타임 orchestration
- 진단 로그와 export 초안

실제 privileged helper 설치, 사용자 승인, 로그인 자동 실행, 업데이트 마이그레이션, 제거 자동화는 **문서화만 되어 있고 아직 구현되지 않았습니다.**

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
- 실제 하드웨어 제어는 포함하지 않음

### Shared

- 모델, capability 타입, XPC DTO, diagnostics 타입
- AppUI/Core/Helper 사이의 계약 계층

### Helper

- XPC helper skeleton
- `fetchControllerStatus`, `selfTest`, `capabilityProbe` 지원
- 실제 privileged helper 설치/승인/충전 제어는 아직 없음

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
2. `swift build` 또는 `ruby BuildSupport/generate_xcodeproj.rb`를 실행합니다.
3. Xcode 또는 SwiftPM으로 `CellCapApp`을 빌드합니다.
4. 앱을 수동으로 실행합니다.

### 현재 불가능한 설치 항목

- 코드 서명된 배포 패키지
- `.app` 번들 내부에 helper를 포함한 설치 자동화
- privileged helper 등록
- launchd/bootstrap 자동 구성
- 로그인 자동 실행 자동 등록

### 문서상 목표 설치 흐름

향후에는 아래 순서를 목표로 합니다.

1. 앱 번들 설치
2. 첫 실행 진단
3. helper 존재/버전 확인
4. 필요 시 helper 설치 및 권한 승인
5. 런타임 capability probe
6. 로그인 자동 실행 선택

현재 저장소에는 이 흐름의 **3~5단계에 필요한 진단 모델과 상태 판정만 준비**되어 있습니다.

## 첫 실행 흐름

현재 코드 기준 첫 실행 시 앱은 아래 순서로 동작합니다.

1. `CellCapApp`이 `EventLogger`, `BatteryMonitor`, `XPCChargeController`, `AppRuntimeOrchestrator`를 조립합니다.
2. `MenuBarViewModel`이 orchestration 스트림을 구독합니다.
3. `AppRuntimeOrchestrator.start()`가 초기 동기화를 시작합니다.
4. 배터리 스냅샷 조회
5. controller status 조회
6. 필요 시 `selfTest`
7. 필요 시 `capabilityProbe`
8. `PolicyEngine`으로 상태 계산
9. UI 상태와 diagnostics summary 갱신

### 첫 실행에서 확인해야 할 진단 항목

- 내장 배터리 감지 여부
- Apple Silicon 여부
- macOS 26+ 여부
- helper 연결 상태
- capability probe 결과
- self-test 결과
- read-only / monitoring-only 전환 사유

### 현재 미완료 항목

- “첫 실행 안내 화면”
- 사용자 친화적 권한/승인 유도 UI
- helper 설치 실패 복구 화면

## helper 승인 절차

현재 저장소에는 **helper 승인 UI/설치 구현이 없습니다.**
다만 실제 구현 시 필요한 절차는 아래와 같이 정리합니다.

### 목표 절차

1. 앱이 helper 필요 여부 판단
2. helper 버전/설치 상태 확인
3. 설치 요청
4. 관리자 승인 또는 시스템 승인 유도
5. helper 재연결 시도
6. 실패 시 `read-only fallback`

### 현재 범위에서 이미 준비된 것

- helper 연결 실패 시 `ControllerStatus`에 반영
- `errorReadOnly` 및 `readOnlyFallback` 상태 계산
- capability probe와 self-test 기록
- 실패 원인 diagnostics 저장

### 아직 없는 것

- `SMJobBless` 또는 동등한 privileged helper 설치 흐름
- 사용자 승인 안내 UI
- 승인 후 재시도 버튼/복구 플로우
- helper 버전 교체 로직

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
- diagnostics

현재 저장소가 아직 제공하지 않는 것은:

- 실제 충전 제어
- 실제 helper 설치/승인
- 로그인 자동 실행 등록
- 자동 업데이트
- 자동 제거

즉, 지금 단계의 프로젝트는 **“실제 설치 가능한 완제품”이 아니라, 이후 시스템 유틸리티 구현을 안전하게 진행하기 위한 검증 가능한 기반 구조**입니다.

## 남은 TODO

- privileged helper 설치/승인 구현
- launch at login 구현
- helper 버전 확인 및 마이그레이션 구현
- persistent diagnostics 저장 경로 정의
- diagnostics export UI 연결
- first-run onboarding/diagnostic 화면
- signed distribution 전략 정리
- 실제 hardware charge control capability 검증
- 업데이트/제거 자동화
