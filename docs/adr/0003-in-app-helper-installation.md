# ADR 0003: 앱 내장 helper와 SMAppService 설치

## 상태
- 채택

## 결정
- helper(`CellCapHelper`)와 LaunchDaemon plist를 앱 번들(`Contents/MacOS`, `Contents/Library/LaunchDaemons`)에 넣고 `SMAppService.daemon(plistName:)`으로 등록한다.
  sudo 스크립트나 pkg로 `/Library/PrivilegedHelperTools`에 복사하던 방식은 폐기하고, 남아 있으면 `legacyInstalled`로 감지해 설치를 막는다.
- label과 Mach 서비스 이름은 `com.shin.cellcap.helper`를 유지한다.
- 앱과 helper는 고정된 자체 서명 인증서 `CellCap Dev`로 서명한다(`BuildSupport/dev/build_install_app.sh`). ad-hoc 서명으로 대체하지 않는다.
- helper는 XPC 연결마다 `setCodeSigningRequirement`로 `identifier "com.shin.cellcap.app" and certificate leaf = H"<helper 자신의 leaf 인증서 SHA-1>"`를 요구한다.
  helper가 인증서로 서명되지 않았으면 모든 연결을 거부한다.
- 앱 안의 helper 제거는 `releaseControl`(충전 한도를 원래 값으로 복원) → `unregister()` 순서로 한다.
  helper를 내린 뒤에는 root 권한이 없어 복원할 수 없으므로, 해제에 실패하면 사용자 확인 없이 제거하지 않는다.

## 이유
- 사용자가 터미널과 sudo 없이 앱 설정에서 helper를 설치/승인/제거할 수 있다.
- 이전 helper는 연결 클라이언트를 검증하지 않아 아무 프로세스나 root 충전 제어를 호출할 수 있었다.

## 실기기에서 확인한 macOS 동작 (macOS 26.7.1, M1 Max)
- 이전 방식 helper의 백그라운드 항목(BTM) 기록은 파일을 지워도 남는다. 같은 label을 등록하면 그 기록에 묶여 helper가 `EX_CONFIG`로 실행되지 않고,
  SMAppService 상태는 등록 전부터 `enabled`로 보인다. `unregister()`를 한 번 호출하면 기록이 지워진다. 그래서 설치는 `enabled`면 먼저 해제한다.
- Team ID가 없는 자체 서명은 helper 바이너리 자체에 실행 허용이 묶인다. 바이너리가 바뀐 뒤 다시 등록하면 `Launch Constraint Violation`으로 실행이 거부되고,
  백그라운드 항목이 `enabled, disallowed`가 되며, SMAppService는 `notRegistered`로 보고한다. 이때 launchd job은 남아 있으므로
  설치 상태 판단은 "미등록 + launchd job 존재"를 `requiresApproval`로 본다. 시스템 설정에서 CellCap을 다시 허용하면 새 바이너리로 실행된다.
- 바이너리가 같으면 제거 후 다시 설치해도 재승인이 필요 없다.
- 서명 인증서가 바뀌어도 재승인이 필요하다. 증분 빌드는 helper를 다시 서명하지 않을 수 있어, 인증서가 바뀌면 clean build를 한다.
- 짧은 시간에 등록/해제를 반복하면 승인 알림이 더 뜨지 않는다(`Exceeded max notifications`). 시스템 설정에서 직접 허용한다.
- SMAppService daemon으로 실행된 root helper에서도 macOS 충전 한도 설정(ADR 0002) 쓰기와 해제가 그대로 동작한다.
- `taskgated-helper`의 `no eligible provisioning profiles found` 로그는 helper에 entitlement가 없어서 생기며 실행에 영향이 없다.

## 결과
- helper 바이너리가 바뀌는 변경은 고급 정보의 `다시 설치` → 시스템 설정 재허용이 필요하다. Developer ID(Team ID) 서명으로 바꾸면 재승인 부담이 줄어들 수 있으나 검증하지 않았다.
- `swift run`처럼 앱 번들 밖에서 실행한 앱은 helper를 설치하거나 연결할 수 없다. 실제 제어 확인은 설치된 앱 번들로 한다.
- 제거 pkg는 helper job을 내리고 충전 한도를 복원한 뒤, 앱의 `--cellcap-uninstall-cleanup`으로 백그라운드 항목 등록 기록을 지운다.
