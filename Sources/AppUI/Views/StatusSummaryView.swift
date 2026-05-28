import Core
import Shared
import SwiftUI

struct StatusSummaryView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            stateHeadline
            batteryProgressBar
            summaryLine
            statusFooter

            if viewModel.isTemporaryOverrideActive {
                temporaryOverrideInline
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
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityHeader)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: viewModel.menuBarSymbolName)
                .font(.title.weight(.semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(viewModel.batteryPercentText)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if shouldShowModeBadge {
                Text(viewModel.controllerModeLabel)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(modeBadgeTint.opacity(0.15), in: Capsule(style: .continuous))
                    .foregroundStyle(modeBadgeTint)
                    .accessibilityLabel("현재 모드: \(viewModel.controllerModeLabel)")
            }
        }
    }

    private var stateHeadline: some View {
        Text(viewModel.chargeStateTitle)
            .font(.title3.weight(.bold))
            .foregroundStyle(tint)
    }

    private var batteryProgressBar: some View {
        let percent = viewModel.appState.battery?.chargePercent ?? 0
        let upper = viewModel.appState.policy.upperLimit
        let recharge = viewModel.appState.policy.rechargeThreshold

        return GeometryReader { geometry in
            let width = geometry.size.width
            let fillFraction = CGFloat(min(100, max(0, percent))) / 100
            let rechargeX = width * CGFloat(min(100, max(0, recharge))) / 100
            let upperX = width * CGFloat(min(100, max(0, upper))) / 100

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.quaternary.opacity(0.6))
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(6, width * fillFraction))

                Rectangle()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: 1.5, height: 14)
                    .offset(x: rechargeX - 0.75)

                Rectangle()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 1.5, height: 14)
                    .offset(x: upperX - 0.75)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private var summaryLine: some View {
        Text(viewModel.summarySentence)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(viewModel.appState.chargeState == .errorReadOnly ? 3 : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusFooter: some View {
        HStack(spacing: 12) {
            statusDot(text: viewModel.powerStatusText, tint: .primary, isMuted: true)
            statusDot(
                text: viewModel.helperStatusText,
                tint: helperTint,
                isMuted: helperTint == .primary
            )
            Spacer(minLength: 0)
        }
    }

    private func statusDot(text: String, tint: Color, isMuted: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var temporaryOverrideInline: some View {
        let progress = viewModel.temporaryOverrideProgress
        let remaining = viewModel.temporaryOverrideRemainingText
        let title = remaining.map { "임시 해제 진행 중 · 남은 시간 \($0)" } ?? "임시 해제 진행 중"

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: "bolt.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Button("종료") {
                    viewModel.clearTemporaryOverride()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityHint("진행 중인 임시 100% 충전을 종료합니다")
            }

            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(CellCapTheme.Palette.stateCharging)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, 4)
    }

    private var tint: Color {
        CellCapTheme.tint(for: viewModel.appState.chargeState)
    }

    private var helperTint: Color {
        switch viewModel.appState.controllerStatus.helperConnection {
        case .connected: return .primary
        case .disconnected, .unavailable: return CellCapTheme.Palette.noticeWarn
        }
    }

    private var shouldShowModeBadge: Bool {
        viewModel.appState.controllerStatus.mode != .fullControl
    }

    private var modeBadgeTint: Color {
        switch viewModel.appState.controllerStatus.mode {
        case .fullControl: return .secondary
        case .readOnly: return CellCapTheme.Palette.noticeWarn
        case .monitoringOnly: return CellCapTheme.Palette.stateSuspended
        }
    }

    private var accessibilityHeader: String {
        "CellCap, \(viewModel.batteryPercentText), \(viewModel.chargeStateTitle). \(viewModel.summarySentence)"
    }
}
