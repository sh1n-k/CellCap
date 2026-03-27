import Core
import Shared
import SwiftUI

struct StatusSummaryView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CellCap")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(viewModel.summarySentence)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(viewModel.controllerModeLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.batteryPercentText)
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                    Text(viewModel.powerStatusText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: viewModel.menuBarSymbolName)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(statusTone.tint)
                    .padding(16)
                    .background(statusTone.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            HStack(spacing: 10) {
                statusBadge
                detailPill(title: "helper", value: viewModel.helperStatusText)
                detailPill(title: "install", value: viewModel.helperInstallStateText)
                detailPill(title: "reason", value: localized(viewModel.transitionReason))
            }

            if let installReason = viewModel.helperInstallReasonText {
                Text(installReason)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            batteryBar
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.14, blue: 0.20),
                            Color(red: 0.06, green: 0.08, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(statusTone.tint.opacity(0.35), lineWidth: 1)
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusTone.tint)
                .frame(width: 10, height: 10)
            Text(viewModel.chargeStateTitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(statusTone.tint.opacity(0.15), in: Capsule())
    }

    private var batteryBar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * CGFloat((Double(viewModel.appState.battery?.chargePercent ?? 0) / 100.0))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [statusTone.tint.opacity(0.75), statusTone.tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(18, width))
            }
        }
        .frame(height: 12)
    }

    private func detailPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusTone: StatusTone {
        StatusTone(state: viewModel.appState.chargeState)
    }

    private func localized(_ reason: ChargeTransitionReason) -> String {
        switch reason {
        case .missingBattery:
            return "배터리 없음"
        case .helperFailure:
            return "helper 실패"
        case .controlSuspended:
            return "제어 중단"
        case .temporaryOverride:
            return "임시 해제"
        case .atUpperLimit:
            return "상한 도달"
        case .belowRechargeThreshold:
            return "하한 도달"
        case .waitingWithinPolicyBand:
            return "정책 대기"
        }
    }
}

private struct StatusTone {
    let tint: Color

    init(state: ChargeState) {
        switch state {
        case .holdingAtLimit:
            tint = Color(red: 0.52, green: 0.81, blue: 0.45)
        case .charging, .temporaryOverride:
            tint = Color(red: 0.95, green: 0.68, blue: 0.19)
        case .waitingForRecharge:
            tint = Color(red: 0.42, green: 0.72, blue: 0.93)
        case .suspended:
            tint = Color(red: 0.60, green: 0.65, blue: 0.72)
        case .errorReadOnly:
            tint = Color(red: 0.93, green: 0.35, blue: 0.31)
        }
    }
}
