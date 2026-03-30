import SwiftUI

struct PolicySettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    private let overrideDurations: [Double] = [30, 60, 120, 240]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: "충전 정책",
                subtitle: "자주 바꾸는 정책을 먼저 두고, 조정 결과를 짧게 읽을 수 있게 정리했습니다."
            )

            VStack(alignment: .leading, spacing: 14) {
                sliderRow(
                    title: "충전 상한",
                    valueText: "\(viewModel.appState.policy.upperLimit)%",
                    explanation: "\(viewModel.appState.policy.upperLimit)%까지 충전한 뒤 멈춥니다.",
                    binding: viewModel.upperLimitBinding,
                    range: 50...100,
                    isEnabled: viewModel.controlAvailability.isEnabled,
                    minHeight: 118,
                    explanationLineLimit: 2
                )

                sliderRow(
                    title: "재충전 하한",
                    valueText: "\(viewModel.appState.policy.rechargeThreshold)%",
                    explanation: "\(viewModel.appState.policy.rechargeThreshold)% 이하가 되면 전원 연결 시 다시 충전합니다.",
                    binding: viewModel.rechargeThresholdBinding,
                    range: 0...Double(viewModel.appState.policy.upperLimit),
                    isEnabled: viewModel.controlAvailability.isEnabled,
                    minHeight: 118,
                    explanationLineLimit: 2
                )
            }

            if let reason = viewModel.controlAvailability.reason {
                disabledCallout(title: viewModel.controlNoticeTitle, reason: reason)
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "임시 100% 충전",
                    subtitle: "출장이나 장거리 이동 전에 상한을 잠시 해제하고, 끝나면 기존 정책으로 돌아갑니다."
                )

                overrideDurationCard
                overrideSummaryCard
                overrideActionRow

                if let reason = viewModel.temporaryOverrideNoticeReason {
                    disabledCallout(title: viewModel.temporaryOverrideNoticeTitle, reason: reason)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "자동 실행 및 복구",
                    subtitle: "로그인 후 앱을 자동으로 열고 저장된 정책을 다시 적용합니다."
                )

                launchAtLoginCard

                if let reason = viewModel.launchAtLoginErrorText {
                    disabledCallout(title: "자동 실행 등록 확인 필요", reason: reason)
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

    private var overrideDurationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Text("선택한 시간 동안 100% 충전을 허용한 뒤, 기존 상한과 하한 정책으로 복귀합니다.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.56))
                .lineLimit(2)
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
    }

    private var overrideSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isTemporaryOverrideActive ? "bolt.fill" : "clock")
                    .foregroundStyle(Color(red: 0.88, green: 0.53, blue: 0.21))

                Text(viewModel.isTemporaryOverrideActive ? "현재 임시 해제가 진행 중입니다" : "준비된 임시 해제")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.8))
            }

            Text(viewModel.temporaryOverrideSummaryText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var overrideActionRow: some View {
        HStack(alignment: .center, spacing: 12) {
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

            Spacer(minLength: 0)
        }
    }

    private var launchAtLoginCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("로그인 시 자동 실행")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.82))

                    Text(viewModel.launchAtLoginStatusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: viewModel.launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Color(red: 0.88, green: 0.53, blue: 0.21))
            }

            Text("자동 실행이 켜져 있으면 앱 시작 직후 helper와 상태를 다시 맞추고 남아 있는 임시 해제 시간도 복구합니다.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.98, green: 0.98, blue: 0.98).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
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
        isEnabled: Bool,
        minHeight: CGFloat,
        explanationLineLimit: Int?
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
                .lineLimit(explanationLineLimit)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
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

struct AdvancedStatusSectionView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                advancedHeader
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            if isExpanded {
                Divider()
                    .padding(.top, 16)
                    .padding(.bottom, 16)

                advancedContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.97, green: 0.96, blue: 0.95).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isExpanded ? Color.black.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    AdvancedStatusMetric(title: "Helper 상태", value: viewModel.helperStatusText)
                    AdvancedStatusMetric(title: "설치 상태", value: viewModel.helperInstallStateText)
                    AdvancedStatusMetric(title: "현재 모드", value: viewModel.controllerModeLabel)
                }

                if let reason = viewModel.helperInstallReasonText {
                    Text(reason)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))
                }

                if let controllerError = viewModel.lastControllerErrorText {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("최근 제어 오류")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.45))

                        Text(controllerError)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.99, green: 0.95, blue: 0.94).opacity(0.99))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(red: 0.91, green: 0.74, blue: 0.69), lineWidth: 1)
                    )
                }

                CapabilityStatusListView(viewModel: viewModel, title: "기능 가능 여부")
            }
        }
    }

    private var advancedHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("고급 정보")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.84))

                    Text("helper 연결, 설치 상태, 기능 가능 여부를 필요할 때만 펼쳐 확인합니다.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.58))

                    Text(viewModel.compactHelperSummaryText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    Text(viewModel.advancedSectionStatusText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            (viewModel.shouldAutoExpandAdvancedSection
                                ? Color(red: 0.96, green: 0.88, blue: 0.83)
                                : Color(red: 0.90, green: 0.96, blue: 0.91)),
                            in: Capsule()
                        )
                        .foregroundStyle(
                            viewModel.shouldAutoExpandAdvancedSection
                                ? Color(red: 0.63, green: 0.24, blue: 0.19)
                                : Color(red: 0.25, green: 0.52, blue: 0.31)
                        )

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.66))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.82), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AdvancedStatusMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.45))

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.78))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}
