# ADR 0002: macOS 충전 한도 기반 helper backend

## 상태
- 채택

## 배경
- macOS 26.7 / 27 펌웨어에서 SMC 충전 키(`CHTE`, `CH0B`, `CH0C`, `CH0I`)가 제거되었다.
  대체 키(`bfD0`/`bfE0`/`bfF0`)와 powerd `chargeSocLimit` XPC는 `com.apple.private.iokit.soc-limit` entitlement가 필요해 root로도 쓸 수 없다.
- macOS 기본 충전 한도의 공개 진입점(`PowerUISmartChargeClient setMCLLimit:`)은 80–100%만 허용한다.
- PowerUIAgent는 root 사용자 도메인 `com.apple.smartcharging.topoffprotection`의 `mclLimitValue`를
  `com.apple.smartcharging.defaultschanged` 알림 때 다시 읽어 범위 검사 없이 powerd에 전달한다(M1 Max, 26.7.1 실측: 5초 내 반영, 20% 수용).

## 결정
- helper는 SMC 충전 키가 있으면 `DirectSMCChargeControlBackend`, 없고 충전 한도 설정이 있으면 `ManagedChargeLimitBackend`를 쓴다(`ChargeControlBackendSelector`).
- XPC 계약 `setChargingEnabled(Bool)`은 유지하고 의미만 매핑한다.
  - 충전 중지: `mclLimitValue = max(20, 현재 SoC)`. 한도와 SoC가 같으면 방전 없이 충전만 멈춘다.
  - 충전 허용: `mclLimitValue = 100`.
  - 충전 중지 상태에서 SoC가 내려가면 한도를 현재 SoC로 낮춘다(래칫). 재연결 시 이전 한도까지 재충전되지 않아 재충전 하한이 지켜진다.
- `MCLFeatureState`는 쓰지 않는다. 알림으로 다시 읽히지 않고, 쓴 뒤 한도 변경이 무시되는 현상이 관측되었다.
- 적용 확인은 `/Library/Preferences/com.apple.powerd.charging.plist`의 `ChargeCtrlPolicy`(reason `manualChargeLimit`)를 읽는다.
  이 파일은 늦게 갱신될 수 있어 120초 grace가 지나도 다를 때만 오류로 본다.
- 최초 개입 전 `mclLimitValue`를 `CellCapHelperXPC.chargeLimitBaselinePath`에 보관하고 uninstall(dev/release)이 복원한다.
- 사용자가 제어를 끄면 Core가 충전 허용 명령을 보내 한도를 해제한다.

## 결과와 한계
- CellCap이 설치되어 있는 동안 macOS 설정의 충전 한도 값은 CellCap이 덮어쓴다. 충전 허용 상태에서는 사용자의 80% 한도도 해제된다.
- 한도는 펌웨어가 잠자기·재부팅 후에도 유지한다. 앱만 삭제하고 helper 제거를 하지 않으면 마지막 한도가 남는다.
- 비공개 경로라 Apple이 막을 수 있다. 적용 실패는 grace 검사로 감지해 read-only로 내려간다.
