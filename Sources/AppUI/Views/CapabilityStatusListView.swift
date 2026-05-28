import Shared
import SwiftUI

struct CapabilityStatusListView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    var title: String = "가능 여부"

    var body: some View {
        let groups = grouped(statuses: viewModel.capabilityReport.statuses)

        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(viewModel.capabilityCountSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("기능 가능 여부 요약: \(viewModel.capabilityCountSummary)")

            if !groups.supported.isEmpty {
                supportedChipGrid(statuses: groups.supported)
            }

            if !groups.notable.isEmpty {
                VStack(spacing: 8) {
                    ForEach(groups.notable, id: \.key) { status in
                        notableCard(for: status)
                    }
                }
            }
        }
    }

    private func supportedChipGrid(statuses: [CapabilityStatus]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(statuses, id: \.key) { status in
                HStack(spacing: 6) {
                    Image(systemName: icon(for: status))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CellCapTheme.tint(for: status.support))
                        .accessibilityHidden(true)
                    Text(viewModel.capabilityTitle(for: status.key))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(.quaternary.opacity(0.4))
                )
                .help(status.reason)
                .accessibilityLabel(
                    "\(viewModel.capabilityTitle(for: status.key)) \(viewModel.capabilityLabel(for: status.support)): \(status.reason)"
                )
            }
        }
    }

    private func notableCard(for status: CapabilityStatus) -> some View {
        let tint = CellCapTheme.tint(for: status.support)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: status))
                .foregroundStyle(tint)
                .font(.callout)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(viewModel.capabilityTitle(for: status.key))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text(viewModel.capabilityLabel(for: status.support))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.15), in: Capsule(style: .continuous))
                        .foregroundStyle(tint)
                }
                Text(status.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CellCapTheme.Corner.medium, style: .continuous)
                .fill(.quaternary.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CellCapTheme.Corner.medium, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    private func grouped(statuses: [CapabilityStatus]) -> (supported: [CapabilityStatus], notable: [CapabilityStatus]) {
        var supported: [CapabilityStatus] = []
        var notable: [CapabilityStatus] = []
        for status in statuses {
            switch status.support {
            case .supported:
                supported.append(status)
            case .experimental, .unsupported, .readOnlyFallback:
                notable.append(status)
            }
        }
        return (supported, notable)
    }

    private func icon(for status: CapabilityStatus) -> String {
        switch status.support {
        case .supported: return "checkmark.circle.fill"
        case .unsupported: return "xmark.octagon.fill"
        case .experimental: return "flask.fill"
        case .readOnlyFallback: return "eye.fill"
        }
    }
}

struct CellCapPanelBackground: View {
    var body: some View {
        Rectangle()
            .fill(.background)
            .overlay(.thinMaterial)
            .ignoresSafeArea()
    }
}
