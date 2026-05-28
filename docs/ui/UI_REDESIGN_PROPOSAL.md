# CellCap UI 전면 개편 제안서

## 0. 문서 목적과 범위

- **목적**: 현재 CellCap 앱의 기능과 데이터 흐름은 그대로 유지한 채, 메뉴 막대 팝오버 UI를 사용자에게 더 명확하고 사용하기 쉽게 보이도록 재정렬하기 위한 디자인 개편안.
- **명시적 비범위**:
  - 기능 추가/삭제, 동작 변경 없음.
  - 라우팅·상태 머신·정책 엔진·XPC/Helper 계약 변경 없음.
  - `Shared` 모델(enum/필드/case)·`MenuBarViewModel`이 노출하는 @Published 신호 변경 없음.
  - `MenuBarPresentation`이 만들어내는 텍스트 사전(예: "상한 유지 중", "임시 해제 중") 자체는 유지(필요 시 다듬기만).
- **변경 허용 범위**: `Sources/AppUI/Views/*`의 View 본문, `RootView.swift`의 컨테이너 구조, 색/타이포/간격/아이콘 사용, 새로운 SwiftUI subview 분리. 즉 "프리젠테이션 레이어 안에서의 시각 재정렬".
- **독자**: 이 개편을 구현하는 후속 작업자(에이전트 또는 사람).

> 본 문서는 코드를 수정하지 않고 작성되었습니다. 모든 근거는 현재 main 브랜치 코드의 실제 심볼·case·파일 위치에 기반합니다. 검증되지 않은 부분은 §10에 명시했습니다.
>
> 시각 자료: 본 문서 §5 화면별 제안에 대응하는 Before/After ASCII 와이어프레임은 [`UI_REDESIGN_WIREFRAMES.md`](./UI_REDESIGN_WIREFRAMES.md)에 정리돼 있습니다.

---

## 1. 앱 개요 (UI 개편의 출발점)

CellCap은 **Apple Silicon / macOS 26+ 전용 배터리 충전 제어 메뉴 막대 유틸리티**입니다 (`README.md`).
사용자가 동의 가능한 환경에서 충전 상한·하한·임시 100% 충전을 제어하고, 그렇지 않은 환경에서는 안전하게 read-only / monitoring-only로 내려갑니다 (`01_기획서.md`).

UI는 단일 메뉴 막대 진입점(`MenuBarExtra` + `.menuBarExtraStyle(.window)`, `Sources/AppUI/CellCapApp.swift:37-41`)으로만 노출되며, 일반적인 윈도우/탭/Settings 윈도우는 없습니다.

핵심 사용자 흐름(코드 기반):

1. 메뉴 막대에서 배터리 아이콘과 % 라벨을 본다 (`MenuBarLabelView.swift`).
2. 라벨을 클릭하면 396×560pt 고정 팝오버가 열린다 (`RootView.swift:31`).
3. 팝오버 최상단의 **요약 카드**에서 현재 배터리 %, 충전 상태 한 줄, helper 상태, 모드, 배터리 진행바를 본다 (`StatusSummaryView.swift`).
4. 그 아래 **정책 카드**에서 상한·하한 슬라이더, 임시 100% 충전 제어, 자동 실행 토글을 조작한다 (`PolicySettingsView.swift`).
5. **고급 정보 카드**(접힘 상태가 기본)를 펼쳐 helper/설치/모드/기능 가능 여부 매트릭스를 확인한다 (`PolicySettingsView.swift:410` `AdvancedStatusSectionView`).
6. 하단의 "**상태 다시 계산**" 버튼으로 강제 재동기화한다 (`RootView.swift:18-24`).

따라서 UI 개편은 이 단일 팝오버 안에서의 **시선 흐름·정보 위계·조작 위치·상태 가독성**만 손보는 일입니다.

---

## 2. 현재 UI 구조 (사실 기반)

### 2.1 진입점과 컨테이너
- `CellCapApp.swift`
  - `MenuBarExtra { RootView(viewModel:) } label: { MenuBarLabelView(viewModel:) }`
  - `.menuBarExtraStyle(.window)`로 클릭 시 윈도우형 팝오버.
- `RootView.swift`
  - `ScrollView { VStack(spacing: 16) { … } .padding(18) }`
  - `.frame(width: 396, height: 560)` — 고정 크기.
  - 배경: `CellCapPanelBackground()` (밝은 베이지→푸른빛 그라데이션 + 두 개의 코너 원, `CapabilityStatusListView.swift:105-130`).
  - 자식 순서: `StatusSummaryView → PolicySettingsView → AdvancedStatusSectionView → "상태 다시 계산" 버튼`.

### 2.2 메뉴 막대 라벨 (`MenuBarLabelView.swift`)
- `HStack(spacing: 5) { menuBarIcon; Text(batteryPercentText) }`.
- 일반 상태에서는 직접 `CGPath`로 그린 18×12pt 커스텀 배터리 템플릿 이미지를 사용.
- `suspended` / `errorReadOnly`일 때만 SF Symbol(`pause.circle`, `exclamationmark.triangle.fill`)로 교체.
- 즉 상태 종류는 라벨에서 **아이콘 모양**으로만 구분되고, 색은 macOS 메뉴 막대 기본 톤(`.primary`).

### 2.3 상단 요약 카드 (`StatusSummaryView.swift`, 155줄)
- 다크 그라데이션 카드(`Color(0.12,0.14,0.20)` → `(0.06,0.08,0.12)`, cornerRadius 26).
- 내부 구성:
  - 1행: 좌측 "CellCap" 제목(26pt heavy) + `summarySentence`(13pt, 2~3줄), 우측 `modeBadge` 캡슐.
  - 2행: 좌측 `batteryPercentText`(48pt heavy) + `powerStatusText`(12pt), 우측 SF Symbol(34pt)이 컬러 박스 안에.
  - 3행: `statusBadge`(작은 원 + `chargeStateTitle`) 캡슐 + `helperStatusText`(12pt 시멘틱 흰색) + "설치 상태 …"(11pt 옅은 흰색).
  - 4행(조건부): `helperInstallReasonText`(11pt secondary, 2줄).
  - 5행: 12pt 높이 `batteryBar` (Capsule + 그라데이션 fill).
- `statusTone`: `ChargeState`별로 5색 팔레트(holdingAtLimit=초록, charging/temporaryOverride=황색, waitingForRecharge=파랑, suspended=회색, errorReadOnly=빨강).

### 2.4 정책 카드 (`PolicySettingsView.swift`, 569줄)
밝은 베이지 카드(cornerRadius 24, `Color(0.97,0.96,0.95)`)에 3개 섹션이 위에서 아래로 쌓이고 사이에 `Divider()`:

**섹션 A — "충전 정책"**
- `sliderRow(title: "충전 상한", range: 50…100, minHeight: 118)`
- `sliderRow(title: "재충전 하한", range: 0…upperLimit, minHeight: 118)`
- 각 행: 좌측 title(13pt bold) + 우측 valueText 캡슐, 아래 SwiftUI `Slider`(step 1), 그 아래 설명 2줄.
- `controlAvailability.isEnabled == false`일 때 `opacity 0.72` + 배경 톤 변경 + 하단에 `disabledCallout`(빨강 톤 callout).

**섹션 B — "임시 100% 충전"**
- `overrideDurationCard`
  - 헤더: "유예 시간" + 선택된 라벨 캡슐(파랑 톤).
  - 본문: 30분/1시간/2시간/4시간 4개의 균등 폭 chip 버튼(`durationChipRow`). 선택 칩은 주황색, 비선택은 흰색 반투명.
  - 설명 2줄.
- `overrideSummaryCard`
  - `bolt.fill` 또는 `clock` 아이콘 + 제목 + `temporaryOverrideSummaryText`(가변 줄).
- `overrideActionRow`
  - 좌측 `Label("임시 해제 시작/종료", systemImage: …)` 버튼 + `OverrideActionButtonStyle`(주황 풀필).
  - 우측은 `Spacer`만 — 명시적 보조 액션 없음.
- 비활성 시 `disabledCallout("지금은 임시 해제를 시작할 수 없습니다", reason)`.

**섹션 C — "자동 실행 및 복구"**
- `launchAtLoginCard`
  - 좌측 "로그인 시 자동 실행" + 상태 텍스트.
  - 우측 `Toggle` switch 스타일(주황 tint).
  - 설명 2줄.

### 2.5 고급 정보 카드 (`AdvancedStatusSectionView`, 같은 파일 410~541줄)
- 헤더(클릭 시 토글, `chevron.up/down`): 제목 + 설명 + `compactHelperSummaryText` 한 줄 + `advancedSectionStatusText` 캡슐("확인 필요"=빨강 톤 / "정상"=초록 톤).
- 펼치면:
  - 3열 메트릭 카드(`AdvancedStatusMetric`): Helper 상태 · 설치 상태 · 현재 모드.
  - 조건부 `helperInstallReasonText`.
  - 조건부 "최근 제어 오류" 박스(연한 분홍 톤).
  - `CapabilityStatusListView(title: "기능 가능 여부")` — `CapabilityKey` 8종에 대해 아이콘+제목+상태 캡슐+사유(2줄)를 카드 리스트로 표시.
- 자동 펼침 조건: `shouldAutoExpandAdvancedSection`(fullControl 아님 / errorReadOnly / 미지원·readOnlyFallback 기능 존재) (`ControlAvailabilityResolver.swift:55-127`).

### 2.6 하단 액션
- `Button("상태 다시 계산", systemImage: "arrow.clockwise")` + `.borderedProminent` + 주황 tint.

### 2.7 ViewModel이 노출하는 표시 상태 (개편 시 그대로 유지)
`MenuBarViewModel.swift`의 `@Published`와 `MenuBarPresenting` 프로토콜은 적어도 다음을 노출합니다:
- `batteryPercentText`, `chargeStateTitle`, `summarySentence`, `powerStatusText`
- `helperStatusText`, `controllerModeLabel`, `helperInstallStateText`, `helperInstallReasonText`, `compactHelperSummaryText`
- `temporaryOverrideSummaryText`, `selectedOverrideDurationLabel`, `advancedSectionStatusText`
- `controlNoticeTitle`, `temporaryOverrideNoticeTitle`, `isReadOnlyPresentation`
- `menuBarSymbolName`, `diagnosticsSummaryText`
- `capabilityLabel(for:)`, `capabilityTitle(for:)`
- 액션: `recomputeState()`, `startTemporaryOverride()`, `clearTemporaryOverride()`, `updateUpperLimit(_:)`, `updateRechargeThreshold(_:)`, `setLaunchAtLoginEnabled(_:)`, `refreshDiagnostics()`, `prepareDiagnosticsExport()`
- 가용성: `controlAvailability`, `temporaryOverrideAvailability`, `shouldAutoExpandAdvancedSection`, `lastControllerErrorText`(고급 섹션에서 참조됨), `temporaryOverrideNoticeReason`, `launchAtLoginErrorText`, `launchAtLoginStatusText`, `isTemporaryOverrideActive`

> 개편 시 이 신호 집합 자체는 건드리지 않습니다. 위계와 표현만 바꿉니다.

---

## 3. 현재 UI의 문제점

> "어떤 코드가 잘못됐다"가 아니라 "사용자가 무엇을 놓치거나 헷갈릴 수 있는가" 관점.

1. **시각 톤이 두 개 따로 산다.**
   상단 요약 카드는 다크 모드 톤(`#1F2433` 계열)인데, 정책 카드·고급 카드는 거의 흰색 + 베이지 라이트 카드. 한 팝오버 안에서 두 디자인 시스템이 겹쳐 보입니다. 다크/라이트 시스템 테마와도 어긋날 수 있습니다.

2. **3개 캡슐(modeBadge / statusBadge / 상태 라벨)이 시각적으로 동급으로 보입니다.**
   각각의 의미는 다릅니다: `controllerModeLabel`(시스템이 우리에게 허용한 권한 모드), `chargeStateTitle`(지금 우리가 어떤 정책 단계인지), 그리고 본문 "임시 해제 중" 같은 라벨. 사용자가 우선순위(=배터리 충전 상태 > 모드 > helper 설치 상세)를 한눈에 잡기 어렵습니다.

3. **상태와 행동의 위치가 분리돼 있습니다.**
   "임시 해제가 진행 중입니다"는 정책 카드 가운데에, "남은 시간/끝내기"는 그 바로 아래 액션 행에 있고, 비활성 사유는 callout으로 또 따로. **활성 중인 임시 해제는 상단 요약 카드에서 즉시 보여야 사용자가 "끄는 곳"을 빨리 찾을 수 있습니다.**

4. **상한/하한 슬라이더가 위계 없이 동등합니다.**
   `rechargeThreshold`는 `upperLimit`에 종속(`range: 0…upperLimit`)인데 시각적으로는 같은 비중. 사용자는 "상한을 먼저 정하고 하한을 그 안에서 정한다"는 관계를 알아내야 합니다.

5. **고급 카드 헤더의 정보가 과합니다.**
   "고급 정보" 제목 + 부제 + `compactHelperSummaryText` + "확인 필요/정상" 캡슐 + chevron. 토글 한 줄에 4종의 시각 요소가 경쟁합니다. 정상일 때는 작게, 문제일 때만 크게 보이는 비대칭이 필요합니다.

6. **`CapabilityStatusListView`가 정보 밀도와 색 사용이 무겁습니다.**
   8개 항목이 모두 각자 카드 + 색 배경 + 캡슐 배지 + 2줄 사유로 표시되어, 사실은 "지원 ✔" 위주의 정상 케이스도 노이즈를 만듭니다.

7. **`disabledCallout` 톤이 강합니다.**
   불가 사유가 모두 빨강 톤이라 "위험"으로 읽힐 수 있습니다. 정작 errorReadOnly·monitoring-only는 안전 모드로의 정상적 하강(failsafe)이므로 emergency가 아닌 "정보/주의" 톤이 더 맞습니다 (§13 기획서 사용자 보호 UX 규칙).

8. **하단의 "상태 다시 계산" 버튼이 시각적으로 가장 강한 주황 풀필이지만, 사용 빈도는 낮은 회복용 액션입니다.**
   `borderedProminent` + 주황 tint가 임시 해제 시작 버튼과 동일한 시각 비중이라 우선순위가 혼란스럽습니다.

9. **반응 영역과 hit target.**
   `overrideDurationCard`의 chip은 균등 폭이지만 높이가 작고, `Toggle`은 우측 끝, `Slider`는 가로 한가운데로, 사용자의 손가락(/포인터) 동선이 흐트러져 있습니다.

10. **국제화 여지 없음.**
    모든 라벨이 한글 하드코딩(`MenuBarPresentation.swift`, `*View.swift`). 개편 시 `LocalizedStringKey`로 통일하면 추후 영문 추가가 무료에 가깝습니다.

11. **메뉴 막대 라벨의 정보 결손.**
    `isReadOnlyPresentation == true`나 `chargeState == .holdingAtLimit`처럼 사용자가 "지금 제어 중인가/관측 중인가"를 라벨만 보고 알 수 있어야 하는데, 현재는 일반 상태에서 같은 커스텀 배터리 아이콘 + %만 보입니다. 비정상(`suspended`, `errorReadOnly`)만 다른 심볼로 전환됩니다.

12. **접근성·다이내믹 타입 미지원.**
    `Text`가 모두 절대 포인트 사이즈(`.font(.system(size: 13, …))`). VoiceOver `accessibilityLabel`이나 `Dynamic Type` 대응이 없어, 시력 보조 사용자나 macOS 텍스트 크기 조정 사용자에게 불리합니다.

13. **고정 396×560pt 프레임.**
    `installReason`이 2줄을 넘는 경우, `helperStatusText` + 진단 메시지가 누적되는 경우 등 콘텐츠가 길어지면 `ScrollView` 안에서 잘립니다. 메뉴 막대 팝오버 특성상 어쩔 수 없는 절충이지만, 정보 위계 재정렬로 "스크롤 없이도 가장 중요한 것이 보이게" 만들 여지가 큽니다.

---

## 4. 공통 디자인 원칙 (개편 가이드)

| 원칙 | 의미 | 적용 |
|---|---|---|
| **하나의 시각 시스템** | 다크/라이트 카드 혼재를 끝낸다. macOS 시스템 머티리얼(`.regularMaterial`/`.thickMaterial`)을 기본으로 둔다. | 모든 카드를 동일 머티리얼 + 단일 액센트 컬러로 통일. |
| **위계는 색이 아니라 크기·여백·위치로 만든다** | 색은 "상태 의미"에만, 위계는 타이포·간격으로. | 강조 색(주황·빨강·황색)은 한 화면에 1~2개로 제한. |
| **상태와 행동을 같은 자리에** | "지금 X 중"이라는 표시 옆에는 항상 "X 끝내기" 버튼이 있다. | 임시 해제 활성 시 요약 카드 안에 종료 버튼 동거. |
| **정상은 조용히, 비정상은 또렷이** | 정상 상태에서 텍스트 노이즈를 줄인다. | CapabilityList 정상 항목은 한 줄, 비정상은 카드. |
| **failsafe는 emergency가 아니다** | read-only/monitoring-only는 "안전 모드"로, 오류로 보이지 않게. | 빨강 → 청회색/노랑 톤, 명도 낮은 callout 사용. |
| **메뉴 막대 라벨은 한 글자만큼의 정보를 더** | 사용자가 팝오버를 열지 않고도 모드를 안다. | 라벨 아이콘에 "유지 중/충전 중/제어 끔" 3단계 변형. |
| **시스템 친화** | macOS 26 메뉴 막대 앱의 표준 컴포넌트를 우선 사용. | `Form`, `LabeledContent`, `GroupBox`, `Section`, SF Symbol Hierarchical 렌더링. |
| **접근성** | 텍스트/색 대비, VoiceOver, Dynamic Type 대응. | 절대 포인트 → `.body`/`.callout`/`.caption`. accessibilityLabel 명시. |
| **재사용 가능한 토큰** | 색·간격·코너를 코드 한 곳에 모은다. | `enum CellCapTheme { static let cornerLarge … }` 또는 `Color` 확장. |

---

## 5. 화면별 개선안

### 5.1 메뉴 막대 라벨 (`MenuBarLabelView`)

**문제 재진술**: 현재 일반 상태에서 라벨은 동일한 커스텀 배터리 아이콘 + %로만 보이며, 사용자가 라벨만 보고 "지금 제어가 살아 있는가/끊겨 있는가"를 알 수 없음. 메뉴 막대는 다른 앱 아이콘과 경쟁하는 가장 좁은 1선 표시 공간.

**개선 방향**:
1. **아이콘에 한 단계 의미를 더한다(기능 변경 아님)**: 이미 `MenuBarPresentation.menuBarSymbolName`이 `ChargeState`별로 5종을 반환하므로, View에서 이 값을 그대로 SF Symbol로 표시해도 충분합니다. 커스텀 `CGPath` 배터리 한 종에 통합하던 분기를 5종 SF Symbol 직사용으로 단순화하면, 시스템 다크/라이트 톤·동적 타이포·VoiceOver를 그대로 받습니다.
2. **`isReadOnlyPresentation == true`일 때 텍스트에 미세 표식**: 예) `"80%"` 옆 0.5pt baseline shift 또는 `eye` 글리프를 inline으로. 색 변경은 메뉴 막대 톤을 깨므로 금지.
3. **숫자 폭 고정**: `.monospacedDigit()` 적용으로 %가 79→80→81로 바뀔 때 좌우 흔들림 제거.
4. **accessibilityLabel**: `"배터리 80%, 상한 유지 중"`처럼 `chargeStateTitle`을 합성. 코드 추가 1줄.

**선택 사항 (검증 필요, §10)**: macOS 메뉴 막대 라벨에서 SF Symbol Hierarchical 렌더링이 의도대로 보이는지 직접 확인. 안 보일 경우 monochrome로 폴백.

---

### 5.2 상단 요약 카드 (`StatusSummaryView`)

**개편 컨셉**: "지금 상태 한 장 + 지금 가능한 행동 1~2개"가 한 화면 안에 끝나도록 재배치.

**제안 구조** (위→아래):

```
┌──────────────────────────────────────────────────────────┐
│  [SF Symbol·상태 톤]   80%                    [모드 배지]  │
│                       상한 유지 중                          │
│  ─────────────────────────────────────────────────────── │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░  80/100  (재충전 75% 이하)    │
│  ─────────────────────────────────────────────────────── │
│  상한에 도달해 충전을 멈추고 유지하고 있습니다.            │
│                                                            │
│  · 전원 연결됨 · helper 연결 정상                          │
└──────────────────────────────────────────────────────────┘
```

구체:

- **카드 톤**: 다크 그라데이션 → `.background(.thickMaterial)` + 얇은 액센트 stroke(상태 톤 0.25 opacity). 시스템 다크/라이트 모두에 자연스럽게 어울리도록.
- **1행**: `Image(systemName: viewModel.menuBarSymbolName)`을 좌측에 두고 hierarchical 렌더링 + 상태 톤. 옆에 `batteryPercentText`(`.system(.largeTitle, design: .rounded).monospacedDigit()`). 우측에 모드 배지 1개만.
- **2행 (상태 한 줄)**: `chargeStateTitle`을 `.title3 bold`로. 이 줄 하나가 "지금 무엇이 일어나고 있나"의 진실. 색은 상태 톤 1회만 사용.
- **3행 (배터리 진행바)**: 현재의 단색 Capsule을 유지하되, **상한(80)과 하한(75) 위치에 얇은 tick mark 2개**를 더해 "지금 어디에 있는가"를 그래프 하나에 통합. tick은 텍스트 라벨 없이 1pt 흰색 가로선만. 데이터는 이미 `appState.policy.upperLimit`, `rechargeThreshold`에 있으므로 새 신호 불필요.
- **4행 (보조 설명)**: `summarySentence`. 현재처럼 `.foregroundStyle(.secondary)`, 2~3줄.
- **5행 (인라인 상태 도트)**: `· 전원 연결됨 · helper 연결 정상` 한 줄. 캡슐 배경 제거, 단순 텍스트 + 작은 색 점. `powerStatusText`, `helperStatusText`를 그대로 합성.
- **모드 배지의 시각 우선순위**: `controllerStatus.mode == .fullControl`일 때는 표시하지 않거나 매우 옅게(=정상은 조용히 원칙). `.readOnly`/`.monitoringOnly`일 때만 노란 톤으로 또렷이.
- **임시 해제 활성 시 카드 안에 종료 버튼 동거**: `isTemporaryOverrideActive == true`이면 5행 자리에 `"임시 해제 진행 중 · 종료까지 1시간 12분"` + `Button("종료")` 한 줄 추가. 사용자가 정책 카드까지 내려가지 않아도 됨. (남은 시간 텍스트는 이미 `temporaryOverrideSummaryText`에 들어갈 수 있는 정보 — 표현 형식만 정리.)

**대체 안 (Variant)**:
- 상단을 두 단으로 (좌: 큰 % + 진행바, 우: 상태 + helper). 폭 396pt에서는 빠듯하므로 1차안에서는 단단(stack) 권장.

---

### 5.3 정책 카드 (`PolicySettingsView`)

#### 5.3.1 섹션 A — 충전 한계 (현: "충전 정책")

**문제**: 상한·하한 슬라이더가 같은 비중. 둘 관계가 안 보임.

**제안**:
- **이중 슬라이더 한 줄로 시각화**: `RangeSlider`(SwiftUI 기본 없음 → `ZStack` + 두 `Slider` 합성, 또는 시각만 합치고 입력은 두 개의 Slider 유지). 데이터 입력은 `viewModel.upperLimitBinding`, `viewModel.rechargeThresholdBinding` 두 개를 그대로 유지 → 기능 변경 없음. 시각만 한 트랙에 두 핸들로 보임.
- **그게 부담스러우면 최소 시각 변경**: 두 Slider를 같은 트랙 폭으로 정렬하되, 두 번째 행의 좌측에 들여쓰기(16pt indent)와 `arrow.turn.down.right` 글리프를 추가해 "상한의 하위 정책"임을 표현.
- **valueText 캡슐을 슬라이더 thumb 위에 옵션으로 표시**: 사용자가 드래그하는 순간만 보이는 floating bubble. 평소엔 텍스트 행 1개로 충분.
- **`isEnabled == false`일 때**: `opacity 0.72`만이 아니라 슬라이더를 점선 트랙 + `lock.fill` 글리프로 명시. 빨강 callout 대신 노란 톤 inline note.

**섹션 헤더 문구**: "충전 정책" → "충전 한계" 정도로 짧게 줄여 위계를 본문에 양보(권고).

#### 5.3.2 섹션 B — 임시 100% 충전

**문제**: 시간 선택 카드 → 상태 요약 카드 → 액션 버튼 → callout이 세로로 4개 따로 쌓여 한 액션이 한 화면을 다 먹음.

**제안 (활성/비활성 두 모드로 단순화)**:

- **비활성 상태**: `GroupBox("임시 100% 충전")` 하나로.
  - 행 1: `Picker("유예 시간", selection: …) { Text("30분").tag(30); … }`.
    - **`.pickerStyle(.segmented)`** 적용 → chip 4개를 segmented control 한 줄로 정렬, 표준 macOS 룩.
    - 데이터 바인딩은 현재 `overrideDurationMinutes`(Double) 그대로.
  - 행 2: 우측 정렬 `Button("지금 임시 해제 시작", systemImage: "bolt.badge.clock")` `.buttonStyle(.borderedProminent)` `.tint(.orange)`.
  - 비활성 사유는 inline `Text` + `info.circle`(노랑/회색) 톤. 카드 빨강 callout 폐기.

- **활성 상태**: 같은 GroupBox 본문이 다음으로 바뀜.
  - 진행바: `ProgressView(value: 남은시간/총시간)`. 현재 `temporaryOverrideSummaryText`에서 시간 정보를 끌어와 시각화. (`appState.policy.isTemporaryOverrideActive(at: now)` + `temporaryOverrideUntil`을 이미 `MenuBarPresentation`이 알고 있음.)
  - 좌측: "임시 해제 진행 중 · 남은 시간 1시간 12분".
  - 우측: `Button("종료", systemImage: "stop.fill")` `.tint(.secondary)`.
  - 본문 1줄 설명(`temporaryOverrideSummaryText`).
- §5.2에서 상단 요약 카드에 종료 버튼을 인라인으로 두면, 이 섹션 안의 버튼은 보조 위치로 격하 가능.

#### 5.3.3 섹션 C — 자동 실행 및 복구

**제안**:
- `LabeledContent("로그인 시 자동 실행") { Toggle("", isOn: …).labelsHidden() }` 표준 macOS 폼 패턴 사용.
- 상태 텍스트(`launchAtLoginStatusText`)와 설명을 한 줄로 합치고 `.foregroundStyle(.secondary)`로 톤 다운.
- 오류는 callout 대신 Toggle 하단 inline 노랑 텍스트.

**섹션 전체에 적용할 패턴**:
- `Divider()` 사용을 줄이고 `VStack(spacing: 24)`로 호흡으로 구분.
- `Form` 또는 `GroupBox`를 적극 활용하면 macOS 표준 룩과 dark/light 적응이 무료.

---

### 5.4 고급 정보 카드 (`AdvancedStatusSectionView`)

**개편 컨셉**: "정상이면 한 줄, 문제가 있으면 펼친다." 헤더의 시각 요소를 줄이고, 본문은 그룹을 적게.

**제안**:

- **헤더 단순화**:
  - 토글: `DisclosureGroup("고급 정보")` 사용. 우측 자동 chevron 제공, 헤더 자체 디자인 부담을 SwiftUI에 위임.
  - 상태 배지: "확인 필요"일 때만 `Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)` 한 글리프. "정상"일 때는 아예 표시하지 않음(정상은 조용히 원칙).
  - `compactHelperSummaryText`는 헤더에서 빼고 본문 첫 줄로 이동.

- **본문 구조**:
  1. `LabeledContent`로 3행: "Helper 상태 / 설치 상태 / 현재 모드" — 3열 카드 대신 2열 정렬 list. (현재 메트릭 카드 디자인은 정보량 대비 면적이 큼.)
  2. `helperInstallReasonText`가 있을 때만 `.callout`(`.secondary` 톤) 한 줄.
  3. "최근 제어 오류"가 있을 때만 노란 톤 `GroupBox` 한 칸.
  4. **`CapabilityStatusListView` 재구성** — 다음 §5.5.

---

### 5.5 기능 가능 여부 (`CapabilityStatusListView`)

**문제**: `CapabilityKey` 8종 모두에 카드+배경+캡슐+사유(2줄)를 주면, "다 정상"인 경우에도 8개의 큰 카드가 펼쳐짐. 정작 unsupported 1개는 그 안에 묻힘.

**제안 (정상은 조용히 / 비정상은 또렷이)**:

- **상단 1줄 요약**: `"8개 항목 · 6 지원 · 1 실험적 · 1 미지원"`처럼 카운트를 한 줄로.
- **본문 리스트를 2층으로 나눔**:
  - **상단 그리드**: `supported` 항목들은 작은 chip(아이콘 + 제목)만. 사유 텍스트는 hover/click 시 popover로. macOS에서는 `.help("…")` modifier로 hover tooltip 처리 가능.
  - **하단 카드**: `unsupported`/`experimental`/`readOnlyFallback`은 현재 카드 형식 유지하되 폭만 통합(전폭). 사유 2줄 그대로.
- **chargeControl + experimental의 특별 색**(현재 `accentColor(for:)`에서 초록으로 분기되는 부분)은 유지. 단, 이는 정말 직관에 어긋날 수 있으므로(실험적인데 초록으로 표시) "초록 + 작은 `flask` 보조 글리프" 조합으로 의미를 분명히.
- **아이콘 세트** 재고: `eye.circle.fill` → `eye.fill` + 작은 캡슐로. SF Symbol 사이즈/렌더링을 hierarchical로 통일.

---

### 5.6 하단 액션 (`recomputeState` 버튼)

**문제**: 시각적으로 가장 강한 주황 풀필이 회복용 액션을 차지.

**제안**:
- 스타일을 `.borderless` + `Label("상태 다시 계산", systemImage: "arrow.clockwise")` `.foregroundStyle(.secondary)`로 약화.
- 위치를 고급 정보 카드 헤더 우측의 작은 아이콘 버튼으로 이동시키는 옵션도 가능(단, 발견성이 떨어지면 안 됨 — 1차안에서는 위치 유지 + 톤만 다운 권장).
- 우측에 `Button("진단 내보내기", systemImage: "square.and.arrow.up")`(이미 `prepareDiagnosticsExport()` 액션 존재)을 보조 액션으로 추가 배치하면, 사용자에게 "회복용 액션이 모인 푸터"라는 인지가 생김.

---

### 5.7 패널 배경 (`CellCapPanelBackground`)

**문제**: 베이지→블루 그라데이션 + 두 개의 코너 원 — 시각적으로 흥미롭지만 다크 모드와 충돌, 카드 자체가 머티리얼이 되면 더 깔끔.

**제안**:
- 그라데이션·코너 원 폐기.
- `.background(.thinMaterial)` 또는 시스템 표준 윈도우 배경.
- 액센트 컬러는 모든 곳에서 단일 `Color.accentColor` 또는 한정된 토큰만 사용.

---

## 6. 공통 디자인 시스템 (토큰)

후속 작업자가 일관되게 적용할 수 있도록 토큰을 모아 둡니다. 코드 추가는 작은 enum 한 개로 충분합니다(View 본문에서만 사용, ViewModel/Shared에는 침투하지 않음).

### 6.1 색 토큰 (상태 의미에만)
| 토큰 | 의미 | 권장 값(개념) |
|---|---|---|
| `accent` | 활성 기본 액션 | `Color.accentColor` (시스템 따름) |
| `stateHolding` | holdingAtLimit | green 60 (현재 `(0.52,0.81,0.45)`와 유사) |
| `stateCharging` | charging / temporaryOverride | orange 60 (`(0.95,0.68,0.19)`) |
| `stateWaiting` | waitingForRecharge | blue 60 (`(0.42,0.72,0.93)`) |
| `stateSuspended` | suspended | gray 50 |
| `stateError` | errorReadOnly | red 60 (`(0.93,0.35,0.31)`) |
| `noticeWarn` | failsafe·권한 사유 | yellow 50 (현 빨강 callout 대체) |
| `noticeInfo` | 정보성 | secondary text |

> View가 직접 R/G/B 리터럴을 쓰지 않고 토큰에서 가져오면, 후일 다크 모드 보정이나 Color Asset 마이그레이션이 쉽습니다.

### 6.2 타이포 토큰
| 용도 | SwiftUI |
|---|---|
| 큰 수치(배터리 %) | `.system(.largeTitle, design: .rounded).monospacedDigit()` |
| 상태 헤드라인(`chargeStateTitle`) | `.title3.bold()` |
| 섹션 제목 | `.headline` |
| 본문/설명 | `.callout` 또는 `.subheadline` |
| 메타/캡션 | `.caption` |
| 보조 텍스트 | `.foregroundStyle(.secondary)` |

→ 절대 포인트(`.system(size: 18)`) 폐기, `Dynamic Type` 자동 대응.

### 6.3 코너·간격
| 토큰 | 값 |
|---|---|
| `cornerLarge` | 20 (요약 카드) |
| `cornerMedium` | 14 (내부 카드/버튼) |
| `cornerSmall` | 8 (배지) |
| `sectionSpacing` | 24 |
| `rowSpacing` | 12 |
| `cardPadding` | 16 |

### 6.4 컴포넌트 가이드
| 용도 | 권장 컴포넌트 |
|---|---|
| 라벨+컨트롤 | `LabeledContent` |
| 폼 섹션 | `GroupBox` / `Form { Section }` |
| 펼침 영역 | `DisclosureGroup` |
| 시간 선택 | `Picker(.segmented)` |
| 토글 | `Toggle(…).toggleStyle(.switch)` |
| 슬라이더 | `Slider` (보조 라벨은 `.help()`) |
| 보조 액션 | `.borderless` + SF Symbol Label |
| 주 액션 | `.borderedProminent` (한 화면에 1개) |

---

## 7. 우선순위 / 단계별 적용

> 각 단계는 **독립적으로 머지 가능**하도록 잘랐습니다. ViewModel/Shared/Helper는 단계 어디서도 건드리지 않습니다.

### Phase 1 — 톤 통일·정상 케이스 단순화 (위험 최소, 효과 큼)
1. `CellCapPanelBackground`를 `.thinMaterial`로 교체.
2. `StatusSummaryView`의 다크 그라데이션을 머티리얼 + 단색 stroke로 교체. 큰 수치 폰트만 유지.
3. `disabledCallout`의 빨강 톤을 노랑 톤으로 변경, 아이콘 `info.circle`.
4. `recomputeState` 버튼을 `.borderless` + secondary 색으로 약화.
5. 절대 포인트 폰트를 SwiftUI 시멘틱 폰트로 일괄 치환.
6. `accessibilityLabel` 추가(요약 카드, 메뉴 막대 라벨, 정책 슬라이더, 임시 해제 버튼, 자동 실행 토글).

> 검증: `swift build` + `swift test` 통과. 메뉴 막대 팝오버 수동 확인.

### Phase 2 — 정보 위계 재배치
7. 상단 요약 카드의 5행 구조를 §5.2 제안대로 재정렬(특히 진행바에 상한/하한 tick).
8. `isTemporaryOverrideActive == true`일 때 요약 카드 안에 종료 버튼 인라인.
9. 정책 카드 섹션 B를 `GroupBox` + `Picker(.segmented)`로 재구성.
10. 정책 카드 섹션 C를 `LabeledContent` + Toggle로 재구성.
11. 정책 카드 섹션 A에 indent + arrow glyph로 상한↔하한 관계 표시.

### Phase 3 — 고급/기능 카드 다이어트
12. `AdvancedStatusSectionView` 헤더를 `DisclosureGroup`으로 교체.
13. `CapabilityStatusListView`를 "정상 chip 그리드 + 비정상 카드"로 2층 분리.
14. "상태 다시 계산" 옆에 "진단 내보내기" 보조 액션 추가.

### Phase 4 — 메뉴 막대 라벨 / 국제화 / 시스템 친화 (선택)
15. `MenuBarLabelView`를 SF Symbol 5종 직사용 + `.monospacedDigit()`로 단순화.
16. 모든 사용자 노출 문자열을 `LocalizedStringKey`로 래핑(이미 한국어 하드코딩 상태이므로 `Localizable.strings(ko)`로 옮기기만 하면 됨).
17. macOS 다크/라이트, "포커스 윈도우 색조" 변경, 텍스트 크기 조정(Reduce Transparency 포함)에서 시각 깨짐 확인.

각 Phase 종료 시 검증(테스트 + 빌드 + 메뉴 막대 팝오버 수동 확인)을 거치고, 시각 큰 변경은 PR에 스크린샷 첨부.

---

## 8. 구현 시 주의사항

1. **ViewModel/Shared/Helper 변경 금지**.
   - `MenuBarViewModel`의 `@Published` 집합, `MenuBarPresenting` 프로토콜, `Shared/Models/*`의 enum case, `ChargePolicy` 필드, `CapabilityKey` 8종을 그대로 사용.
   - 새 표시용 변환이 필요하면 **View 내 private computed property**로 처리하고, 가능하면 추후 `MenuBarPresentation`으로 옮기는 PR을 별도로.

2. **고정 폭 396pt를 깨지 말 것** (Phase 1~3 한정).
   - 메뉴 막대 팝오버는 `MenuBarExtra(.window)` 특성상 사용자가 폭을 못 늘림. `Picker(.segmented)`가 좁아 보일 수 있으므로 4 segment를 2×2 그리드로 자동 전환할지 검증.

3. **`StatusTone`을 한 곳으로 모으기**.
   - 현재 `StatusSummaryView` 내부 `private struct StatusTone`에 색이 박혀 있고, `CapabilityStatusListView`·`PolicySettingsView`도 R/G/B 리터럴을 쓴다. 새 색 토큰 enum을 만들어 두 곳에서 같은 색을 참조하면 일관성이 자동 보장됨.

4. **자동 펼침 로직(`shouldAutoExpandAdvancedSection`) 유지**.
   - `RootView.swift:33-40`의 `onAppear`/`onChange`를 그대로 두면 `DisclosureGroup`에도 `isExpanded` 바인딩을 전달 가능. 동작 변경 없음.

5. **다크/라이트 모두에서 검증**.
   - 현재 라이트 카드 톤(`(0.97,0.96,0.95)`)은 다크 모드 시스템 메뉴와 부조화. 머티리얼로 바꾸면 자동 해결되지만, 임의 색은 반드시 `Asset Catalog`나 `Color.adaptive(...)`로 분기.

6. **VoiceOver 텍스트 결합 순서**.
   - 요약 카드에서 큰 % 숫자가 먼저 읽히고, 그 다음 상태가 읽히도록 `accessibilityElement(children: .combine)` + `accessibilityLabel` 명시.

7. **미리보기 보존**.
   - `RootView.swift:44-50`, 각 View의 `#Preview`가 `previewHolding()`, `previewErrorReadOnly()` 등 `MenuBarPreviewFactory`에 의존. 개편 후에도 이 프리뷰가 깨지지 않게 시그니처 변경 금지.

8. **`UninstallCleanupCommand`와 무관**.
   - UI 개편은 cleanup 경로(`Sources/AppUI/UninstallCleanupCommand.swift`)와 무관. 변경하지 않음.

9. **테스트 영향**.
   - `Tests/AppUITests`는 순수 로직(ViewModel/Presenter) 테스트가 중심. View 구조만 바뀌므로 빨강은 거의 없을 것이나, "스냅샷 테스트"가 추가돼 있다면(현재 없음) 업데이트 필요.
   - `Tests/CoreTests`는 영향 없음.

10. **점진적 머지**.
    - Phase별로 PR을 쪼개고, 각 PR은 스크린샷 + GIF 1장씩. UI 변화는 텍스트 diff만으로 리뷰가 어렵습니다.

---

## 9. 사용자 시점의 Before / After 시나리오

### 시나리오 A: "지금 임시 해제 중인 걸 끄고 싶다"
- **Before**: 라벨 클릭 → 팝오버 열림 → 요약 카드 본다 → 상태 캡슐 "임시 해제 중" 확인 → 정책 카드까지 스크롤 → 임시 100% 충전 섹션 안 → "임시 해제 종료" 버튼 클릭. **시선 이동 4단계, 스크롤 1회.**
- **After**: 라벨 클릭 → 요약 카드 안 "임시 해제 진행 중 · 1시간 12분 남음" 옆 "종료" 클릭. **시선 이동 1단계, 스크롤 없음.**

### 시나리오 B: "지금 helper가 안 되는 것 같다, 왜인지 보고 싶다"
- **Before**: 요약 카드의 작은 흰색 글씨 `helper 연결 끊김 · 설치 상태 미설치` 확인 → 고급 정보 카드 펼치기 → 사유 텍스트 + Capability 8개 카드 스크롤 → 사유 찾기.
- **After**: 요약 카드 5행에 도트 + `· helper 연결 끊김` → 우측 `info.circle` 클릭(또는 자동 펼침된 `DisclosureGroup` 본문에서 노랑 callout 1개) → `helperInstallReasonText` 한 줄에서 사유 확인. 정상 capability들은 chip으로만 표시되어 가려지지 않음.

### 시나리오 C: "상한을 75로 낮추고 싶다"
- **Before**: 정책 카드 펼침 → 상한 슬라이더 드래그 → 하한이 자동으로 조정될 수 있다는 사실은 슬라이더 range로만 암시.
- **After**: 한 트랙에 두 핸들 → 상한 핸들 드래그 → 하한 핸들이 따라 움직이는 것이 시각적으로 보임. 또는 indent + arrow glyph로 하한이 상한의 하위 정책임을 인지.

### 시나리오 D: "전부 정상인지 한눈에 보고 싶다"
- **Before**: 요약 카드 다크 그라데이션 + 캡슐 3개 → 정책 카드 라이트 → 고급 카드 헤더 캡슐("정상") → 토글 안 펼침. 톤 차이 때문에 "다 정상"이 직관적으로 안 옴.
- **After**: 한 톤(머티리얼) + 상태 색은 진행바와 헤드라인 한 줄에만. 모드 배지·고급 배지가 정상일 때 숨겨져 화면이 조용. "조용함 = 정상" 신호.

---

## 10. 검증되지 않은 부분 / 한계

- **메뉴 막대 SF Symbol Hierarchical 렌더링**: macOS 26 메뉴 막대에서 `.symbolRenderingMode(.hierarchical)`이 의도대로 색을 받는지 실기기 확인 필요.
- **RangeSlider 구현**: SwiftUI 기본 컴포넌트가 아님. 직접 구현 시 hit target/접근성에 주의. 기능 위험이 있다면 "두 슬라이더 + indent"로 후퇴.
- **`Picker(.segmented)` 좁은 폭**: 4 segment가 396pt 안에서 한국어 "30분/1시간/2시간/4시간"이 잘리지 않는지 실측 필요. 잘릴 경우 2×2 그리드 chip 유지.
- **`temporaryOverrideSummaryText`에서 남은 시간 파싱**: 현재 이 텍스트가 자유서식이므로 진행바·"남은 시간 X" 분리를 위해서는 `MenuBarPresentation`에 새 computed property가 필요할 수 있음. 본 문서는 **Presentation 추가는 허용**(기존 신호 제거·변경은 금지)으로 가정.
- **다크/라이트, Reduce Transparency, Increase Contrast** 환경에서 머티리얼이 카드 위계를 충분히 만드는지 실측 필요.
- **국제화 잔여**: `Localizable.strings(ko)`로 옮긴 뒤에도 일부 동적 텍스트(`"\(percent)%"`, `selectedOverrideDurationLabel`)는 포맷 분리 필요.
- **사용자 리서치 데이터 없음**: 본 제안은 코드 구조와 일반적인 macOS HIG·기획서 §13(사용자 보호 UX 규칙)에 근거한 것이며, 실제 사용자 인터뷰/테스트 결과가 아닙니다.

---

## 11. 부록 — 코드 위치 인덱스 (개편 작업 시 빠른 점프)

| 영역 | 파일 | 핵심 위치 |
|---|---|---|
| 진입점 / 의존성 조립 | `Sources/AppUI/CellCapApp.swift` | `MenuBarExtra { RootView } label: { MenuBarLabelView }` (37-41) |
| 팝오버 컨테이너 | `Sources/AppUI/RootView.swift` | `ScrollView { VStack(spacing:16) }` (7-30), frame 396×560 (31) |
| 메뉴 막대 라벨 | `Sources/AppUI/Views/MenuBarLabelView.swift` | `HStack(spacing:5)` (8-14), 커스텀 배터리 (32-81) |
| 상단 요약 카드 | `Sources/AppUI/Views/StatusSummaryView.swift` | 본문 (8-89), modeBadge (91), statusBadge (99), batteryBar (112), StatusTone (138-155) |
| 정책 카드 본문 | `Sources/AppUI/Views/PolicySettingsView.swift` | 섹션 A (15-41), 섹션 B (45-58), 섹션 C (62-73) |
| 임시 해제 컴포넌트 | 같은 파일 | overrideDurationCard (86), overrideSummaryCard (121), overrideActionRow (149), 버튼 스타일 (~390) |
| 자동 실행 카드 | 같은 파일 | launchAtLoginCard (176) |
| 고급 정보 섹션 | 같은 파일 | `AdvancedStatusSectionView` (410-541), `AdvancedStatusMetric` (543-569) |
| 기능 가능 리스트 | `Sources/AppUI/Views/CapabilityStatusListView.swift` | 본문 (4-55), 색 분기 (70-102) |
| 패널 배경 | 같은 파일 | `CellCapPanelBackground` (105-130) |
| 표시 변환 | `Sources/AppUI/ViewModels/MenuBarPresentation.swift` | 프로토콜 (4-24), 본문 (26-319) |
| 가용성 | `Sources/AppUI/ViewModels/ControlAvailabilityResolver.swift` | (전체) |
| 자동 펼침 트리거 | `RootView.swift` | (33-40) |
| 모델 case (변경 금지) | `Sources/Shared/Models/ChargeState.swift`, `CapabilityReport.swift`, `ChargePolicy.swift`, `ControllerStatus.swift`, `HelperInstallStatus.swift` | — |

---

**마무리**: 이 제안은 한 줄로 요약하면 "**다크 카드 + 라이트 카드 + 빨강 callout의 혼재를 끝내고, 시스템 머티리얼 한 톤 위에 상태와 행동을 한 화면에서 끝낼 수 있게 재정렬한다**"입니다. 기능·데이터·계약은 그대로 두고, 사용자가 "지금 무엇이 일어나고 있고, 내가 무엇을 할 수 있는가"를 한 시선에서 잡을 수 있게 하는 데 모든 변경이 집중됩니다.
