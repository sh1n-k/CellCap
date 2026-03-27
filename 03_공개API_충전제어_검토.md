# 충전 제어 경로 검토 메모

## 결론

공개 전원 API만으로는 충전 on/off 또는 charge limit 쓰기 경로를 확인하지 못했다. 따라서 현재 구현은 **외부 의존성 없이 Helper 내부에서 AppleSMC를 직접 읽고 쓰는 private backend**를 사용한다.

즉, 이 문서의 결론은 “충전 제어 불가”가 아니라 다음과 같다.

- 공개 API만으로는 부족하다.
- 실제 제어는 Helper 내부 private SMC backend로 수행한다.
- 권한/설치/검증 실패 시 앱은 즉시 `readOnly` 또는 `monitoringOnly`로 내려간다.

## 확인 근거

### 1. 현재 코드에서 사용 중인 공개 API

- `IOPSCopyPowerSourcesInfo`
- `IOPSCopyPowerSourcesList`
- `IOPSGetPowerSourceDescription`
- `IOPSGetProvidingPowerSourceType`

이 경로는 현재 [BatteryMonitor.swift](/Users/shin/PersonalProjects/CellCap-public-api-gate/Sources/Core/Monitoring/BatteryMonitor.swift)와 [SystemBatterySnapshotProvider.swift](/Users/shin/PersonalProjects/CellCap-public-api-gate/Sources/Core/Monitoring/SystemBatterySnapshotProvider.swift)에서 사용 중이며, 모두 **관측(read-only)** 목적이다.

### 2. macOS 26.4 SDK 헤더 확인

로컬 SDK:

```bash
xcrun --sdk macosx --show-sdk-path
```

확인한 핵심 헤더:

```text
/Applications/Xcode.app/.../MacOSX26.4.sdk/System/Library/Frameworks/IOKit.framework/Headers/ps/IOPowerSources.h
```

이 헤더는 전원 소스 상태 조회와 변경 알림을 설명하지만, 충전 on/off 또는 charge limit를 설정하는 public function은 제공하지 않는다.

### 3. 현재 helper/XPC 상태

- [CellCapHelperService.swift](/Users/shin/PersonalProjects/CellCap-public-api-gate/Sources/Helper/CellCapHelperService.swift)는 Helper 내부 backend를 통해 capability probe, self-test, 충전 on/off, temporary override를 처리한다.
- [DirectSMCChargeControlBackend.swift](/Users/shin/PersonalProjects/CellCap-public-api-gate/Sources/Helper/DirectSMCChargeControlBackend.swift)는 직접 AppleSMC 상태를 읽고, 충전 on/off를 쓴다.
- [CellCapSMCBridge.c](/Users/shin/PersonalProjects/CellCap-public-api-gate/Sources/CellCapSMCBridge/CellCapSMCBridge.c)는 C bridge로 AppleSMC user client를 연다.

## 제품 판단

현재 전제에서는:

- 지원 환경 + root helper + SMC 키 확인에 성공하면 `fullControl`을 허용한다.
- helper 권한이 없거나 명령 검증에 실패하면 `readOnly`로 즉시 격하한다.
- 기기/OS/배터리 조건이 맞지 않으면 `monitoringOnly`로 남긴다.
- diagnostics에는 fallback 사유와 마지막 명령 실패를 기록한다.

## 다음 단계

1. 실기기에서 Helper를 root 권한으로 실행 가능한 상태까지 설치 흐름을 확정한다.
2. SMC write 후 상태 재조회가 일치하는지 검증한다.
3. sleep/wake, 전원 연결/해제, helper 재연결 시 read-only fallback이 안전하게 동작하는지 검증한다.
