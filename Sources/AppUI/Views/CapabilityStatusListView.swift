import Shared
import SwiftUI

struct CapabilityStatusListView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("가능 여부")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.84))

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
                                    .foregroundStyle(Color.black.opacity(0.82))

                                Spacer()

                                Text(viewModel.capabilityLabel(for: status.support))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(color(for: status.support).opacity(0.20), in: Capsule())
                                    .foregroundStyle(color(for: status.support))
                            }

                            Text(status.reason)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.68))
                        }
                    }
                    .padding(14)
                    .background(
                        backgroundColor(for: status.support),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(color(for: status.support).opacity(0.22), lineWidth: 1)
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

    private func backgroundColor(for support: CapabilitySupport) -> Color {
        switch support {
        case .supported:
            return Color(red: 0.98, green: 0.99, blue: 0.98).opacity(0.98)
        case .unsupported:
            return Color(red: 0.99, green: 0.95, blue: 0.94).opacity(0.99)
        case .experimental:
            return Color(red: 0.99, green: 0.97, blue: 0.92).opacity(0.99)
        case .readOnlyFallback:
            return Color(red: 0.93, green: 0.96, blue: 1.0).opacity(0.99)
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
                Color(red: 0.93, green: 0.90, blue: 0.86),
                Color(red: 0.86, green: 0.88, blue: 0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            ZStack {
                Circle()
                    .fill(Color(red: 0.89, green: 0.69, blue: 0.43).opacity(0.16))
                    .frame(width: 220, height: 220)
                    .offset(x: 170, y: -140)

                Circle()
                    .fill(Color(red: 0.28, green: 0.40, blue: 0.57).opacity(0.12))
                    .frame(width: 180, height: 180)
                    .offset(x: -180, y: 180)
            }
        )
        .ignoresSafeArea()
    }
}
