# CellCap

Apple Silicon / macOS 26+ 전용 배터리 충전 제어 앱의 초기 구현 골격입니다.

이번 단계의 목적은 실제 하드웨어 제어가 아니라, 다음 단계 구현이 흔들리지 않도록 도메인 구조와 핵심 타입을 먼저 고정하는 것입니다.

## 현재 범위

- `AppUI / Core / Shared / Helper` 4개 타깃 분리
- `CellCap.xcodeproj` 생성 및 재생성 스크립트 추가
- 배터리/정책/컨트롤러 상태 모델 정의
- 충전 상태 머신 초안 정의
- `ChargeController` 추상화와 `MockChargeController` 제공
- 최소 단위 테스트 추가

## 프로젝트 구조

```text
CellCap/
├── .gitignore
├── CellCap.xcodeproj/
├── BuildSupport/
│   └── generate_xcodeproj.rb
├── Package.swift
├── README.md
├── Sources/
│   ├── AppUI/
│   │   ├── CellCapApp.swift
│   │   └── RootView.swift
│   ├── Core/
│   │   ├── Controllers/
│   │   │   ├── ChargeController.swift
│   │   │   └── MockChargeController.swift
│   │   └── StateMachine/
│   │       └── ChargeStateMachine.swift
│   ├── Helper/
│   │   └── main.swift
│   └── Shared/
│       └── Models/
│           ├── AppState.swift
│           ├── BatterySnapshot.swift
│           ├── ChargePolicy.swift
│           ├── ChargeState.swift
│           └── ControllerStatus.swift
└── Tests/
    └── CoreTests/
        ├── ChargePolicyTests.swift
        ├── ChargeStateMachineTests.swift
        └── MockChargeControllerTests.swift
```

## 타깃 역할

### AppUI

- SwiftUI 기반 앱 진입점
- 현재는 도메인 타입을 시각적으로 확인하는 최소 화면만 포함
- 실제 메뉴 막대 UI, 설정 화면, 사용자 액션 연결은 다음 단계에서 구현
- Xcode 프로젝트에서는 macOS app 타깃으로 배치

### Core

- 순수 비즈니스 로직 계층
- 상태 머신, 정책 계산, 제어기 추상화 배치
- UI, XPC, IOKit 같은 구체 구현에 의존하지 않음

### Shared

- 타깃 간 공용 모델과 DTO 배치
- AppUI/Core/Helper가 같은 의미의 타입을 공유
- 추후 XPC 계약 타입도 이 계층으로 확장 예정

### Helper

- 저수준 충전 제어를 담당할 실행 단위의 자리
- 이번 단계에서는 capability probe와 self-test를 위한 stub만 제공
- 실제 privileged helper/XPC bootstrap은 미구현
- Xcode 프로젝트에서는 command line tool 타깃으로 우선 승격

## Xcode 프로젝트

네이티브 Xcode 작업을 위해 `CellCap.xcodeproj`를 생성해 두었습니다.

- 생성 스크립트: `BuildSupport/generate_xcodeproj.rb`
- 현재 타깃: `AppUI`, `Core`, `Shared`, `Helper`, `CoreTests`
- 패키지(`Package.swift`)는 빠른 CLI 테스트와 타입 검증 용도로 유지

재생성:

```bash
ruby BuildSupport/generate_xcodeproj.rb
```

## 핵심 모델

### `BatterySnapshot`

- 시스템/헬퍼/캐시 등 관측 출처를 함께 보관
- 실제 시스템 상태를 source of truth로 삼기 위한 최소 필드만 정의

### `ChargePolicy`

- 상한(`upperLimit`)
- 재충전 하한(`rechargeThreshold`)
- 일시적 해제(`temporaryOverrideUntil`)
- 사용자 또는 시스템에 의한 제어 중지(`isControlEnabled`)

### `ControllerStatus`

- 제어 가능 모드(`fullControl`, `readOnly`, `monitoringOnly`)
- helper 연결 상태
- 최근 오류, override 상태, 충전 허용 상태

### `AppState`

- UI가 필요한 도메인 상태를 하나로 묶는 루트 상태
- 전역 싱글턴 대신 명시적 의존성 주입을 전제로 설계

### `ChargeState`

- `charging`
- `holdingAtLimit`
- `waitingForRecharge`
- `temporaryOverride`
- `suspended`
- `errorReadOnly`

## 상태 머신 초안

`ChargeStateMachine`은 입력 컨텍스트(`BatterySnapshot`, `ChargePolicy`, `ControllerStatus`, `now`)만으로 다음 상태를 결정합니다.

우선순위는 아래 순서입니다.

1. 배터리 미탑재 또는 관측 불가면 `suspended`
2. helper/XPC 오류면 `errorReadOnly`
3. 제어 비활성 또는 full control 불가면 `suspended`
4. temporary override 활성 중이면 `temporaryOverride`
5. 배터리 %가 상한 이상이면 `holdingAtLimit`
6. 배터리 %가 하한 이하이면 `charging`
7. 그 외 구간은 `waitingForRecharge`

이 우선순위는 이후 `PolicyEngine`, `BatteryMonitor`, `XPC`가 붙어도 유지될 수 있는 최소 규칙만 반영합니다.

## ChargeController 추상화

`ChargeController`는 실제 헬퍼/XPC 구현을 숨기기 위한 경계입니다.

```swift
public protocol ChargeController: Sendable {
    func setChargingEnabled(_ enabled: Bool) async throws
    func setTemporaryOverride(until: Date?) async throws
    func getControllerStatus() async -> ControllerStatus
    func selfTest() async -> ControllerSelfTestResult
}
```

이번 단계에서는 `MockChargeController`만 포함하며, 테스트와 UI 프리뷰에서 동일 인터페이스를 사용하게 만듭니다.

## 테스트

다음 검증만 우선 포함합니다.

- 기본 정책값 계산
- temporary override 시간 판정
- 상태 머신 우선순위
- mock controller 명령 기록

실행:

```bash
swift test
```

## 다음 단계 TODO

- `PolicyEngine` 구현
- 시스템 배터리 관측 계층(`BatteryMonitor`) 구현
- 메뉴 막대 UI 및 설정 화면 구현
- Shared XPC DTO 및 Helper 통신 구조 추가
- capability probe 구체화
- privileged helper 설치/권한 처리 설계
