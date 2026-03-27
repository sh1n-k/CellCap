import Shared
import SwiftUI

struct CapabilityStatusListView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("가능 여부")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            VStack(spacing: 10) {
                ForEach(viewModel.capabilityReport.statuses, id: \.key) { status in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: status.support))
                            .foregroundStyle(color(for: status.support))
                            .frame(width: 18, height: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(viewModel.capabilityTitle(for: status.key))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))

                                Spacer()

                                Text(viewModel.capabilityLabel(for: status.support))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(color(for: status.support).opacity(0.14), in: Capsule())
                            }

                            Text(status.reason)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(color(for: status.support).opacity(0.14), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func icon(for support: CapabilitySupport) -> String {
        switch support {
        case .supported:
            return "checkmark.circle.fill"
        case .unsupported:
            return "xmark.circle.fill"
        case .experimental:
            return "flask.fill"
        case .readOnlyFallback:
            return "eye.circle.fill"
        }
    }

    private func color(for support: CapabilitySupport) -> Color {
        switch support {
        case .supported:
            return Color(red: 0.31, green: 0.66, blue: 0.37)
        case .unsupported:
            return Color(red: 0.82, green: 0.27, blue: 0.23)
        case .experimental:
            return Color(red: 0.91, green: 0.60, blue: 0.18)
        case .readOnlyFallback:
            return Color(red: 0.36, green: 0.53, blue: 0.80)
        }
    }
}

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        Label {
            Text(viewModel.batteryPercentText)
        } icon: {
            Image(systemName: viewModel.menuBarSymbolName)
        }
    }
}

struct CellCapPanelBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.94, blue: 0.90),
                Color(red: 0.91, green: 0.92, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            ZStack {
                Circle()
                    .fill(Color(red: 0.94, green: 0.73, blue: 0.47).opacity(0.18))
                    .frame(width: 220, height: 220)
                    .offset(x: 170, y: -140)

                Circle()
                    .fill(Color(red: 0.32, green: 0.44, blue: 0.62).opacity(0.10))
                    .frame(width: 180, height: 180)
                    .offset(x: -180, y: 180)
            }
        )
        .ignoresSafeArea()
    }
}
