import Shared
import SwiftUI

struct PolicySettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    private let overrideDurations: [Double] = [30, 60, 120, 240]

    var body: some View {
        VStack(alignment: .leading, spacing: CellCapTheme.Spacing.section) {
            chargeLimitsSection
            temporaryOverrideSection
            launchAtLoginSection
        }
        .padding(CellCapTheme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CellCapTheme.Corner.large, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CellCapTheme.Corner.large, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }

    // MARK: - Charge limits (SOT §5.3.1)

    private var chargeLimitsSection: some View {
        let isEnabled = viewModel.controlAvailability.isEnabled

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "충전 한계", lockIcon: !isEnabled)

            limitRow(
                title: "충전 상한",
                valueText: "\(viewModel.appState.policy.upperLimit)%",
                binding: viewModel.upperLimitBinding,
                range: 50...100,
                indent: false,
                isEnabled: isEnabled
            )

            limitRow(
                title: "재충전 하한",
                valueText: "\(viewModel.appState.policy.rechargeThreshold)%",
                binding: viewModel.rechargeThresholdBinding,
                range: 0...Double(viewModel.appState.policy.upperLimit),
                indent: true,
                isEnabled: isEnabled
            )

            Text("상한 도달 시 정지, 하한 이하로 내려가면 다시 충전을 시작합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = viewModel.controlNoticeReason {
                InlineNotice(title: viewModel.controlNoticeTitle, detail: reason, tone: .warn)
            }
        }
    }

    private func limitRow(
        title: String,
        valueText: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        indent: Bool,
        isEnabled: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if indent {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .leading)

            Slider(value: binding, in: range, step: 1)
                .disabled(!isEnabled)
                .accessibilityValue(valueText)
                .accessibilityLabel(title)

            Text(valueText)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .opacity(isEnabled ? 1 : 0.55)
    }

    // MARK: - Temporary override (SOT §5.3.2)

    private var temporaryOverrideSection: some View {
        let isEnabled = viewModel.temporaryOverrideAvailability.isEnabled
        let isActive = viewModel.isTemporaryOverrideActive

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "임시 100% 충전", lockIcon: !isEnabled && !isActive)

            if isActive {
                temporaryOverrideActive
            } else {
                temporaryOverrideInactive(isEnabled: isEnabled)
            }

            if !isActive, let reason = viewModel.temporaryOverrideNoticeReason {
                InlineNotice(title: viewModel.temporaryOverrideNoticeTitle, detail: reason, tone: .warn)
            }
        }
    }

    @ViewBuilder
    private func temporaryOverrideInactive(isEnabled: Bool) -> some View {
        let durationBinding = Binding<Int>(
            get: { Int(viewModel.overrideDurationMinutes.rounded()) },
            set: { viewModel.overrideDurationMinutes = Double($0) }
        )

        HStack(spacing: 10) {
            Text("유예 시간")
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .leading)

            Picker("유예 시간", selection: durationBinding) {
                ForEach(overrideDurations, id: \.self) { duration in
                    Text(label(for: duration)).tag(Int(duration))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!isEnabled)
        }

        HStack {
            Text("선택한 시간 동안 100% 충전을 허용한 뒤 기존 정책으로 복귀합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                viewModel.startTemporaryOverride()
            } label: {
                Label("시작", systemImage: "bolt.badge.clock")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(CellCapTheme.Palette.stateCharging)
            .disabled(!isEnabled)
            .accessibilityHint("선택한 \(viewModel.selectedOverrideDurationLabel) 동안 100% 충전을 허용합니다")
        }
        .opacity(isEnabled ? 1 : 0.7)
    }

    private var temporaryOverrideActive: some View {
        let progress = viewModel.temporaryOverrideProgress
        let remaining = viewModel.temporaryOverrideRemainingText
        let title = remaining.map { "진행 중 · 남은 시간 \($0)" } ?? "진행 중"

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "bolt.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Button {
                    viewModel.clearTemporaryOverride()
                } label: {
                    Label("종료", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(CellCapTheme.Palette.stateCharging)
                    .accessibilityHidden(true)
            }

            Text(viewModel.temporaryOverrideSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Launch at login (SOT §5.3.3)

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("로그인 시 자동 실행") {
                Toggle("", isOn: viewModel.launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("로그인 시 자동 실행")
            }
            .font(.callout.weight(.medium))

            Text(launchAtLoginCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = viewModel.launchAtLoginErrorText {
                InlineNotice(title: "자동 실행 등록 확인 필요", detail: error, tone: .warn)
            }
        }
    }

    private var launchAtLoginCaption: String {
        let status = viewModel.launchAtLoginStatusText
        let trailing = "시작 직후 helper와 정책, 남은 임시 해제 시간을 복구합니다."
        if status.isEmpty {
            return trailing
        }
        return "\(status) · \(trailing)"
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, lockIcon: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CellCapTheme.Palette.stateCharging)
                .frame(width: 3, height: 18)
                .accessibilityHidden(true)

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            if lockIcon {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(CellCapTheme.Palette.noticeWarn)
                    .accessibilityLabel("잠금: 지금은 변경할 수 없습니다")
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private func label(for duration: Double) -> String {
        switch Int(duration.rounded()) {
        case 30: return "30분"
        case 60: return "1시간"
        case 120: return "2시간"
        case 240: return "4시간"
        default: return "\(Int(duration.rounded()))분"
        }
    }
}

// MARK: - Advanced section (SOT §5.4)

struct AdvancedStatusSectionView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton

            if isExpanded {
                advancedContent
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .padding(CellCapTheme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CellCapTheme.Corner.large, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CellCapTheme.Corner.large, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: CellCapTheme.Corner.large, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private var headerButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
                    .accessibilityHidden(true)

                Text("고급 정보")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                if viewModel.shouldAutoExpandAdvancedSection {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(CellCapTheme.Palette.noticeWarn)
                        .accessibilityLabel("확인이 필요한 항목이 있습니다")
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "고급 정보 닫기" : "고급 정보 펼치기")
        .accessibilityAddTraits(.isButton)
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusGrid

            if let reason = viewModel.helperInstallReasonText {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let controllerError = viewModel.lastControllerErrorText {
                InlineNotice(title: "최근 제어 오류", detail: controllerError, tone: .warn)
            }

            Divider()

            CapabilityStatusListView(viewModel: viewModel, title: "기능 가능 여부")
        }
    }

    private var statusGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            statusRow(label: "Helper 상태", value: viewModel.helperStatusText)
            statusRow(label: "설치 상태", value: viewModel.helperInstallStateText)
            statusRow(label: "현재 모드", value: viewModel.controllerModeLabel)
        }
        .font(.callout)
    }

    private func statusRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
