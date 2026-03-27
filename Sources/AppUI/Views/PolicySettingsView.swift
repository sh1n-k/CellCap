import SwiftUI

struct PolicySettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: "충전 정책",
                subtitle: "상한과 재충전 하한을 바로 조정합니다."
            )

            VStack(alignment: .leading, spacing: 14) {
                sliderRow(
                    title: "충전 상한",
                    valueText: "\(viewModel.appState.policy.upperLimit)%",
                    explanation: "\(viewModel.appState.policy.upperLimit)%에서 충전을 멈춥니다.",
                    binding: viewModel.upperLimitBinding,
                    range: 50...100
                )

                sliderRow(
                    title: "재충전 하한",
                    valueText: "\(viewModel.appState.policy.rechargeThreshold)%",
                    explanation: "\(viewModel.appState.policy.rechargeThreshold)% 이하일 때만 다시 충전합니다.",
                    binding: viewModel.rechargeThresholdBinding,
                    range: 0...Double(viewModel.appState.policy.upperLimit)
                )
            }
            .disabled(!viewModel.controlAvailability.isEnabled)

            if let reason = viewModel.controlAvailability.reason {
                disabledReason(reason)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "임시 100% 충전",
                    subtitle: "출장이나 장거리 이동 전에 상한을 잠시 해제합니다."
                )

                Picker("유예 시간", selection: $viewModel.overrideDurationMinutes) {
                    Text("30분").tag(30.0)
                    Text("1시간").tag(60.0)
                    Text("2시간").tag(120.0)
                    Text("4시간").tag(240.0)
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.temporaryOverrideAvailability.isEnabled)

                HStack(spacing: 10) {
                    Button {
                        if viewModel.isTemporaryOverrideActive {
                            viewModel.clearTemporaryOverride()
                        } else {
                            viewModel.startTemporaryOverride()
                        }
                    } label: {
                        Label(
                            viewModel.isTemporaryOverrideActive ? "임시 해제 종료" : "임시 해제 시작",
                            systemImage: viewModel.isTemporaryOverrideActive ? "pause.circle.fill" : "bolt.badge.clock"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.88, green: 0.53, blue: 0.21))
                    .disabled(!viewModel.temporaryOverrideAvailability.isEnabled)

                    if viewModel.isTemporaryOverrideActive {
                        Text(viewModel.summarySentence)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                if let reason = viewModel.temporaryOverrideAvailability.reason {
                    disabledReason(reason)
                }
            }

            if !compact {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(
                        title: "현재 제어 모드",
                        subtitle: "실제 helper 구현 전까지는 모드와 불가 사유를 먼저 노출합니다."
                    )

                    HStack(spacing: 12) {
                        Text(viewModel.controllerModeLabel)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.08), in: Capsule())

                        Text(viewModel.helperStatusText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func sliderRow(
        title: String,
        valueText: String,
        explanation: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(valueText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.06), in: Capsule())
            }

            Slider(value: binding, in: range, step: 1)
                .tint(Color(red: 0.88, green: 0.53, blue: 0.21))

            Text(explanation)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func disabledReason(_ reason: String) -> some View {
        Label(reason, systemImage: "lock.slash")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.73, green: 0.26, blue: 0.21))
    }
}

struct SettingsSceneView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CellCap 설정")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("상태 확인과 정책 편집을 분리하지 않고 한 화면에서 함께 조정합니다.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        StatusSummaryView(viewModel: viewModel)
                        CapabilityStatusListView(viewModel: viewModel)
                    }

                    PolicySettingsView(viewModel: viewModel, compact: false)
                        .frame(maxWidth: 360)
                }
            }
            .padding(22)
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(CellCapPanelBackground())
    }
}

#Preview("설정 화면 - 관측 전용") {
    SettingsSceneView(viewModel: .previewMonitoringOnly())
}
