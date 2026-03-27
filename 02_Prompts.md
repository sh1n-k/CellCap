당신은 macOS 시스템 유틸리티를 구현하는 시니어 Swift 엔지니어입니다.

목표는 Apple Silicon / macOS 26+ 전용 배터리 충전 제어 앱의 구현 뼈대를 만드는 것입니다.
이번 단계에서는 기능을 끝내려 하지 말고, 구조와 핵심 타입을 고정하는 것만 수행하십시오.

[이번 단계 목표]

* 프로젝트 구조 확정
* 타깃 분리(AppUI / Core / Shared / Helper)
* 핵심 모델 정의
* 상태 머신 정의
* ChargeController 추상화 정의
* Mock 구현 제공
* README 초안 작성

[반드시 지킬 원칙]

* UI보다 도메인 구조를 먼저 만든다.
* 실제 저수준 충전 제어는 구현하지 않는다.
* 불확실한 부분은 TODO/stub/capability check로 남긴다.
* 컴파일 가능한 최소 골격을 우선한다.
* 전역 상태를 만들지 않는다.
* 테스트 가능 구조로 설계한다.

[핵심 모델]

* BatterySnapshot
* ChargePolicy
* ControllerStatus
* AppState
* ChargeState

  * charging
  * holdingAtLimit
  * waitingForRecharge
  * temporaryOverride
  * suspended
  * errorReadOnly

[필수 추상화]

* ChargeController protocol

  * setChargingEnabled(_ enabled: Bool)
  * setTemporaryOverride(until: Date?)
  * getControllerStatus()
  * selfTest()

[출력 순서]

1. 프로젝트 디렉터리 구조
2. 각 타깃 역할 설명
3. 핵심 모델 코드
4. 상태 머신 정의
5. ChargeController 프로토콜 및 Mock 구현
6. 최소 테스트 코드 초안
7. README 초안

설계 이유를 짧게 설명하면서 진행하십시오.
이번 단계에서는 1~7까지만 수행하십시오.

---

이전 단계에서 만든 프로젝트 구조와 타입을 유지한 채, 이번 단계에서는 정책 엔진과 상태 계산 로직만 구현하십시오.

[이번 단계 목표]

* PolicyEngine 구현
* ChargeStateResolver 구현
* 충전 상한/하한 계산
* temporary override 처리
* state transition 규칙 구현
* 단위 테스트 보강

[정책 규칙]

* battery >= upperLimit 이면 holdingAtLimit
* battery <= rechargeThreshold 이면 charging
* override 활성 시 temporaryOverride
* 제어 불가 환경이면 suspended
* helper/XPC 실패 시 errorReadOnly

[구현 요구]

* 순수 로직으로 작성할 것
* UI 의존성 금지
* 테스트 우선
* Mock ChargeController와 연동 가능하게 유지
* source of truth 우선순위를 고려한 상태 계산 훅을 둘 것

[출력 순서]

1. PolicyEngine 코드
2. ChargeStateResolver 코드
3. 정책 계산 예시
4. 상태 전이 표
5. 단위 테스트 코드
6. 경계 조건 설명

이번 단계에서는 UI, XPC, Helper 구현은 하지 마십시오.

---

이번 단계에서는 macOS의 배터리/전원 상태를 읽는 계층을 구현하십시오.
실제 충전 제어는 하지 말고, 관측 계층만 만드십시오.

[이번 단계 목표]

* BatteryMonitor 구현
* 시스템 배터리/전원 상태를 BatterySnapshot으로 변환
* 전원 연결 상태 감지
* sleep/wake 재동기화 훅 추가
* CapabilityChecker 초안 작성

[원칙]

* 공개 API 기반 읽기 기능에 집중
* 제어 기능과 혼합하지 말 것
* 상태 변경 감지 지점을 분리할 것
* 테스트/Mock 가능한 인터페이스를 둘 것

[출력 순서]

1. BatteryMonitor 구조 설명
2. BatteryMonitor 코드
3. 상태 갱신 흐름
4. CapabilityChecker 초안
5. sleep/wake 대응 골격
6. 테스트 또는 시뮬레이션 방법

이번 단계에서는 메뉴 막대 UI와 Helper 제어 구현은 하지 마십시오.

---

이번 단계에서는 SwiftUI 기반 메뉴 막대 UI와 설정 화면을 구현하십시오.

[이번 단계 목표]

* 메뉴 막대 앱 기본 UI
* 현재 배터리 상태 표시
* 현재 ChargeState 표시
* upperLimit / rechargeThreshold 설정 UI
* temporary override 시작 UI
* 현재 제어 모드 표시
* 불가능한 기능 비활성화 및 이유 표시

[UI 원칙]

* 상태를 한 문장으로 명확히 보여줄 것
* 정상 제한 유지와 제어 실패를 시각적으로 구분할 것
* unsupported 기능은 숨기지 말고 비활성화 + 사유 표시
* 과도한 UI보다 설정과 상태 확인에 집중할 것

[출력 순서]

1. 메뉴 막대 앱 구조
2. 상태 표시 View
3. 설정 View
4. ViewModel 또는 상태 연결 구조
5. 미리보기/Preview 예시
6. UI에서 고려한 사용자 보호 UX 설명

이번 단계에서는 Helper 실제 제어 구현은 하지 마십시오.

---

이번 단계에서는 App/Core와 Helper 사이의 XPC 기반 통신 구조를 구현하십시오.

[이번 단계 목표]

* Shared XPC 인터페이스 정의
* Helper 타깃 골격 작성
* 요청/응답 DTO 정의
* selfTest 경로 구현
* capabilityProbe 경로 구현
* 통신 실패 시 에러 전달 구조 작성

[중요 원칙]

* 실제 저수준 충전 제어는 stub로 둔다.
* XPC 계약(interface)을 먼저 안정적으로 정의한다.
* Helper는 UI를 직접 알지 못하게 한다.
* 실패 시 read-only fallback에 필요한 정보를 반환하게 한다.

[출력 순서]

1. XPC 인터페이스 설계
2. Shared DTO 코드
3. Helper 골격 코드
4. selfTest / capabilityProbe 예시
5. App 측 연결 코드 초안
6. 에러 처리 구조 설명

이번 단계에서는 실제 하드웨어 충전 제어 구현은 하지 마십시오.

---

이번 단계에서는 지금까지 만든 Core, BatteryMonitor, UI, XPC/Helper 골격을 연결하여 앱 서비스 계층을 통합하십시오.

[이번 단계 목표]

* 앱 시작 시 초기 동기화 흐름 구성
* BatteryMonitor → PolicyEngine → UI 업데이트 연결
* Helper 상태 조회 연결
* Scheduler 또는 orchestration 계층 구성
* sleep/wake, power source change, app launch 시 재평가 흐름 연결

[핵심 요구]

* source of truth 우선순위를 반영할 것
* 상태 불일치 시 재동기화 루틴을 둘 것
* Helper 연결 실패 시 자동으로 read-only 상태 반영
* 의존성 방향을 깨지 말 것

[출력 순서]

1. 전체 런타임 흐름 설명
2. orchestration 계층 코드
3. 상태 업데이트 흐름
4. 재동기화 루틴
5. read-only fallback 연결
6. 통합 테스트 초안

이번 단계에서도 실제 저수준 충전 제어는 stub 상태를 유지하십시오.

---

이번 단계에서는 로그, 진단, export 기능을 구현하십시오.

[이번 단계 목표]

* EventLogger 구현
* 정책 변경/상태 전이/helper 통신/오류 로그 기록
* capability probe 결과 저장
* self-test 결과 저장
* 진단 요약 모델 작성
* 로그 export 기능 초안 작성

[원칙]

* 디버깅에 필요한 최소 구조화 로그를 남길 것
* 사용자에게 보여줄 요약과 내부 로그를 구분할 것
* 민감 정보는 저장하지 말 것
* read-only / monitoring-only 전환 원인이 추적 가능해야 함

[출력 순서]

1. 로그 이벤트 모델
2. EventLogger 코드
3. 진단 요약 구조
4. export 기능 초안
5. UI 연결 포인트
6. 운영/debugging 관점 설명

---

이번 단계에서는 설치, helper 승인, 로그인 자동 실행, 업데이트, 제거 흐름을 정리하고 프로젝트 문서를 마무리하십시오.

[이번 단계 목표]

* 설치 절차 문서화
* 첫 실행 진단 흐름 문서화
* helper 승인 절차 정리
* 로그인 자동 실행 구성 정리
* 업데이트 시 helper 마이그레이션 고려사항 정리
* 제거 절차 정리
* README 최종본 작성

[출력 순서]

1. 설치 흐름
2. 첫 실행 흐름
3. 로그인 자동 실행 처리
4. 업데이트 고려사항
5. 제거 절차
6. README 최종본
7. 남은 TODO 목록

구현 완료를 주장하지 말고, 현재 구현 범위와 미완료 항목을 명확히 구분하십시오.

---

이번 단계에서는 실제 저수준 충전 제어 구현을 무리하게 완성하려 하지 말고, 현재 구조에 안전하게 연결 가능한 구현 후보와 통합 지점을 정리하십시오.

[이번 단계 목표]

* ChargeController 실제 구현 후보 구조 설계
* capability gate 설계
* unsupported 환경 차단 규칙 정리
* stub → real implementation 교체 지점 명확화
* 실패 시 즉시 read-only로 전환되는 보호 규칙 명시

[중요]

* 검증되지 않은 동작을 사실처럼 구현하지 말 것
* 하드웨어/OS 의존 부분은 명확히 격리할 것
* 현재 단계에서는 self-test 가능한 최소 연결 구조까지만 제안 가능
* 불확실한 부분은 TODO와 리스크로 남길 것

[출력 순서]

1. 실제 구현 연결 지점
2. capability gate 설계
3. real controller 후보 골격
4. stub와의 교체 방식
5. 안전 정책 반영 방식
6. 남은 리스크 정리
