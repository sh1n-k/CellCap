# ADR 0001: Runtime Synchronization And Helper Boundaries

## 상태
- 채택

## 결정
- `AppRuntimeOrchestrator`는 동기화 순서 조립과 스트림 broadcast만 담당한다.
- helper 설치 상태 병합, self-test 실행 정책, safety gate, controller 명령 적용은 별도 타입으로 분리한다.
- helper 설치 경로와 서비스명은 Swift 계약 계층과 shell 공통 파일에서만 관리한다.

## 이유
- 런타임 동기화와 helper 설치 규칙은 둘 다 위험하지만 변경 이유가 다르다.
- 동기화 로직은 앱 상태 계산과 회귀 테스트의 대상이고, helper 설치 로직은 운영 절차와 시스템 권한의 대상이다.
- 둘을 같은 파일에 계속 섞어 두면 에이전트가 UI 수정이나 정책 수정 중에 위험 스크립트까지 건드리기 쉬워진다.

## 결과
- 동기화 단계는 테스트 가능한 순수 타입으로 쪼갠다.
- helper 설치 스크립트는 공통 상수 파일을 통해 중복을 줄인다.
- 운영 절차는 README에 요약하고, 유지보수 규칙은 `AGENTS.md`에서 고정한다.
