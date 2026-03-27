import SwiftUI

struct PolicySettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    let compact: Bool

    private let overrideDurations: [Double] = [30, 60, 120, 240]

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
                    range: 50...100,
                    isEnabled: viewModel.controlAvailability.isEnabled
                )

                sliderRow(
                    title: "재충전 하한",
                    valueText: "\(viewModel.appState.policy.rechargeThreshold)%",
                    explanation: "\(viewModel.appState.policy.rechargeThreshold)% 이하일 때만 다시 충전합니다.",
                    binding: viewModel.rechargeThresholdBinding,
                    range: 0...Double(viewModel.appState.policy.upperLimit),
                    isEnabled: viewModel.controlAvailability.isEnabled
                )
            }

            if let reason = viewModel.controlAvailability.reason {
                disabledCallout(title: viewModel.controlNoticeTitle, reason: reason)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "임시 100% 충전",
                    subtitle: "출장이나 장거리 이동 전에 상한을 잠시 해제합니다."
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("유예 시간")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.78))
                        Spacer()
                        Text(viewModel.selectedOverrideDurationLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.85, green: 0.91, blue: 1.0), in: Capsule())
                            .foregroundStyle(Color(red: 0.22, green: 0.38, blue: 0.72))
                    }

                    durationChipRow

                    Text("임시 해제 길이는 유지되며, 지금은 조작만 잠겨 있습니다.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.56))
                        .opacity(viewModel.temporaryOverrideAvailability.isEnabled ? 0 : 1)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.95, blue: 0.96).opacity(0.98))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )

                HStack(spacing: 10) {
                    Button {
                        guard viewModel.temporaryOverrideAvailability.isEnabled else { return }
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
                    .buttonStyle(
                        OverrideActionButtonStyle(
                            isEnabled: viewModel.temporaryOverrideAvailability.isEnabled,
                            isActive: viewModel.isTemporaryOverrideActive
                        )
                    )
                    .allowsHitTesting(viewModel.temporaryOverrideAvailability.isEnabled)

                    if viewModel.isTemporaryOverrideActive || viewModel.isReadOnlyPresentation {
                        Text(viewModel.summarySentence)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.58))
                    }
                }

                if let reason = viewModel.temporaryOverrideNoticeReason {
                    disabledCallout(title: viewModel.temporaryOverrideNoticeTitle, reason: reason)
                }
            }

            if !compact {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(
                        title: "현재 제어 모드",
                        subtitle: "직접 제어는 helper 권한과 backend 상태에 따라 달라지므로 모드와 사유를 먼저 노출합니다."
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

                    Text("설치 상태: \(viewModel.helperInstallStateText)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    if let reason = viewModel.helperInstallReasonText {
                        Text(reason)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.97, green: 0.96, blue: 0.95).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.84))
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.58))
        }
    }

    private func sliderRow(
        title: String,
        valueText: String,
        explanation: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        isEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.82))
                Spacer()
                Text(valueText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        (isEnabled ? Color.black.opacity(0.06) : Color(red: 0.89, green: 0.91, blue: 0.94))
                            .opacity(0.96),
                        in: Capsule()
                    )
                    .foregroundStyle(Color.black.opacity(0.75))
            }

            Slider(value: binding, in: range, step: 1)
                .tint(Color(red: 0.88, green: 0.53, blue: 0.21))
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.72)

            Text(explanation)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.58))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isEnabled ? Color(red: 0.98, green: 0.98, blue: 0.98).opacity(0.98) : Color(red: 0.95, green: 0.95, blue: 0.96).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isEnabled ? Color.black.opacity(0.05) : Color(red: 0.86, green: 0.88, blue: 0.91), lineWidth: 1)
        )
    }

    private var durationChipRow: some View {
        HStack(spacing: 10) {
            ForEach(overrideDurations, id: \.self) { duration in
                let isSelected = Int(viewModel.overrideDurationMinutes.rounded()) == Int(duration)
                let isEnabled = viewModel.temporaryOverrideAvailability.isEnabled

                Button {
                    guard isEnabled else { return }
                    viewModel.overrideDurationMinutes = duration
                } label: {
                    Text(label(for: duration))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(chipBackground(isSelected: isSelected, isEnabled: isEnabled), in: Capsule())
                        .foregroundStyle(chipForeground(isSelected: isSelected, isEnabled: isEnabled))
                        .overlay(
                            Capsule()
                                .stroke(chipBorder(isSelected: isSelected, isEnabled: isEnabled), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isEnabled)
            }
        }
    }

    private func disabledCallout(title: String, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "lock.slash")
                Text(title)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.63, green: 0.24, blue: 0.19))

            Text(reason)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.30, blue: 0.28))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.99, green: 0.95, blue: 0.93))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.91, green: 0.74, blue: 0.69), lineWidth: 1)
        )
    }

    private func label(for duration: Double) -> String {
        switch Int(duration.rounded()) {
        case 30:
            return "30분"
        case 60:
            return "1시간"
        case 120:
            return "2시간"
        case 240:
            return "4시간"
        default:
            return "\(Int(duration.rounded()))분"
        }
    }

    private func chipBackground(isSelected: Bool, isEnabled: Bool) -> Color {
        if isSelected {
            return isEnabled
                ? Color(red: 0.55, green: 0.73, blue: 0.98)
                : Color(red: 0.84, green: 0.90, blue: 0.98)
        }
        return isEnabled
            ? Color.white.opacity(0.88)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }

    private func chipForeground(isSelected: Bool, isEnabled: Bool) -> Color {
        if isSelected {
            return isEnabled ? .white : Color(red: 0.23, green: 0.37, blue: 0.66)
        }
        return Color.black.opacity(isEnabled ? 0.72 : 0.62)
    }

    private func chipBorder(isSelected: Bool, isEnabled: Bool) -> Color {
        if isSelected {
            return isEnabled ? Color(red: 0.42, green: 0.59, blue: 0.86) : Color(red: 0.73, green: 0.81, blue: 0.93)
        }
        return Color.black.opacity(0.08)
    }
}

private struct OverrideActionButtonStyle: ButtonStyle {
    let isEnabled: Bool
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(backgroundColor(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(foregroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
    }

    private var foregroundColor: Color {
        isEnabled ? .white : Color(red: 0.41, green: 0.34, blue: 0.30)
    }

    private var borderColor: Color {
        if isEnabled {
            return isActive ? Color(red: 0.70, green: 0.40, blue: 0.19) : Color(red: 0.79, green: 0.48, blue: 0.22)
        }
        return Color(red: 0.87, green: 0.80, blue: 0.73)
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if isEnabled {
            let base = isActive
                ? Color(red: 0.72, green: 0.42, blue: 0.21)
                : Color(red: 0.88, green: 0.53, blue: 0.21)
            return pressed ? base.opacity(0.88) : base
        }

        return Color(red: 0.95, green: 0.89, blue: 0.82)
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
