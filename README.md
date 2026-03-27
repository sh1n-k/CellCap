# CellCap

Apple Silicon / macOS 26+ 전용 배터리 충전 제어 앱을 목표로 하는 macOS 시스템 유틸리티입니다.
현재 저장소는 `AppUI / Core / Shared / Helper`로 분리된 SwiftPM 프로젝트이며, 개발용 privileged helper 수동 설치 스크립트를 포함합니다.

직접 충전 제어는 Helper 내부의 비문서화된 AppleSMC backend를 전제로 합니다.
배포형 helper 설치, 자동 승인, 로그인 자동 실행은 아직 구현되지 않았습니다.

## 문서
- 유지보수 규칙: [AGENTS.md](./AGENTS.md)
- 런타임/Helper 경계 결정: [docs/adr/0001-runtime-and-helper-boundaries.md](./docs/adr/0001-runtime-and-helper-boundaries.md)
- 공개 API 검토 메모: [03_공개API_충전제어_검토.md](./03_%EA%B3%B5%EA%B0%9CAPI_%EC%B6%A9%EC%A0%84%EC%A0%9C%EC%96%B4_%EA%B2%80%ED%86%A0.md)

## 구조
```text
Sources/AppUI     SwiftUI 화면과 표시용 상태 해석
Sources/Core      정책 계산, 런타임 동기화, 진단, 관측, XPC 클라이언트
Sources/Shared    AppUI/Core/Helper 공용 계약과 모델
Sources/Helper    privileged helper와 직접 SMC backend
BuildSupport/dev  helper 설치/상태/재시작/제거 스크립트
Tests/CoreTests   Core/Helper 회귀 테스트
Tests/AppUITests  AppUI 순수 로직 테스트
```

## 개발과 검증
```bash
swift build
swift test
```

Xcode 프로젝트가 필요하면 아래 명령으로 재생성합니다.

```bash
ruby BuildSupport/generate_xcodeproj.rb
```

CI는 GitHub Actions에서 `swift build`, `swift test`만 강제합니다.
root 권한이 필요한 helper smoke test는 자동화하지 않고 수동 절차로 유지합니다.

## 개발용 helper 절차
1. `swift build`
2. `sudo BuildSupport/dev/install_helper.sh`
3. `BuildSupport/dev/helper_status.sh`
4. 앱 실행 후 `Helper 설치`, `Helper 권한`, `충전 제어` 상태 확인
5. 필요하면 `sudo BuildSupport/dev/restart_helper.sh`
6. 정리 시 `sudo BuildSupport/dev/uninstall_helper.sh`

기본 경로는 아래와 같습니다.

- helper 바이너리: `/Library/PrivilegedHelperTools/com.shin.cellcap.helper`
- launchd plist: `/Library/LaunchDaemons/com.shin.cellcap.helper.plist`
- stdout 로그: `/Library/Logs/CellCap/com.shin.cellcap.helper.stdout.log`
- stderr 로그: `/Library/Logs/CellCap/com.shin.cellcap.helper.stderr.log`

`install_helper.sh`는 SwiftPM 산출물의 `CellCapHelper`를 우선 찾고, 필요하면 `CELLCAP_HELPER_BINARY` 또는 첫 번째 인자로 경로를 받을 수 있습니다.

## 수동 점검
실기기 검증이 필요할 때는 아래 순서를 따릅니다.

1. helper 설치와 launchd 등록 확인
2. 앱에서 helper 설치/권한/capability 표시 확인
3. 상한 이하/하한 이하에서 충전 중단과 재개가 기대대로 반영되는지 확인
4. sleep/wake 이후 재동기화가 일어나는지 확인
5. helper 중지 또는 연결 실패 시 `read-only` 또는 `errorReadOnly`로 안전하게 격하되는지 확인

문제 추적 시 자주 쓰는 명령:

```bash
BuildSupport/dev/helper_status.sh
launchctl print system/com.shin.cellcap.helper
tail -n 100 /Library/Logs/CellCap/com.shin.cellcap.helper.stdout.log
tail -n 100 /Library/Logs/CellCap/com.shin.cellcap.helper.stderr.log
```

## 현재 미완료 항목
- 배포형 privileged helper 설치/승인 흐름
- 로그인 자동 실행
- helper 버전 교체 자동화
- 사용자용 first-run / 복구 UI

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
