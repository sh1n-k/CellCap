# CellCap Agent Rules

이 문서는 이 저장소의 최우선 유지보수 규칙입니다.
문서 우선순위는 `AGENTS.md` > 코드 인접 문서 > `README.md` 입니다.

## 디렉터리 책임
- `Sources/AppUI`: SwiftUI 화면, 표시 문구, 메뉴 막대 상호작용
- `Sources/Core`: 정책 계산, 런타임 동기화, 진단, 관측, XPC 클라이언트
- `Sources/Shared`: AppUI/Core/Helper 계약 모델과 XPC DTO
- `Sources/Helper`: privileged helper, backend, helper 진단
- `BuildSupport`: helper 설치/상태/재시작/제거 스크립트와 개발 보조 도구

## 어디에 무엇을 작성하는가
- UI 표시 문구와 표시용 상태 해석은 `Sources/AppUI`에 둔다.
- 정책 계산과 상태 전이는 `Sources/Core/Policy`, `Sources/Core/StateMachine`에 둔다.
- 런타임 동기화 순서, safety gate, helper 제어 적용은 `Sources/Core/Runtime`에 둔다.
- XPC 계약, helper 경로, contract version은 `Sources/Shared/XPC`에 둔다.
- helper 설치/상태 확인 shell 스크립트는 `BuildSupport/dev`에만 둔다.

## 금지 패턴
- helper 서비스명, 설치 경로, 로그 경로, contract version 상수를 임의 위치에 추가하지 않는다.
- UI 계층에서 정책 계산이나 helper/XPC 계약을 복제하지 않는다.
- `AppUI`에서 `Helper` 구현 타입을 직접 참조하지 않는다.
- 위험 스크립트나 SMC backend를 검증 없이 수정한 뒤 병합하지 않는다.

## helper 상수 변경 규칙
- helper 서비스명, 경로, 버전을 바꿀 때는 `Sources/Shared/XPC/CellCapHelperXPCProtocol.swift`와 `BuildSupport/dev/helper_common.sh`를 함께 수정한다.
- shell 스크립트는 공통 경로 정의를 직접 다시 선언하지 않는다.

## 표준 검증
- `swift build`
- `swift test`

## 위험 작업
- 다음 변경은 별도 검토 대상으로 취급한다.
- helper 설치/제거 스크립트
- `Sources/Helper/DirectSMCChargeControlBackend.swift`
- XPC 계약과 DTO

## 구현 기본 원칙
- 기능보다 구조와 책임 경계를 먼저 고정한다.
- 작은 책임 단위로 나누고, 같은 역할의 코드를 여러 위치에 흩뿌리지 않는다.
- 불확실한 운영 규칙은 README가 아니라 이 문서나 코드 인접 ADR에 고정한다.
