import Shared
import SwiftUI

enum CellCapTheme {
    enum Corner {
        static let large: CGFloat = 20
        static let medium: CGFloat = 14
        static let small: CGFloat = 8
    }

    enum Spacing {
        static let section: CGFloat = 18
        static let row: CGFloat = 12
        static let cardPadding: CGFloat = 16
        static let popoverPadding: CGFloat = 16
    }

    enum Palette {
        static let stateHolding = Color(red: 0.36, green: 0.70, blue: 0.40)
        static let stateCharging = Color(red: 0.93, green: 0.62, blue: 0.18)
        static let stateWaiting = Color(red: 0.36, green: 0.62, blue: 0.92)
        static let stateSuspended = Color(red: 0.55, green: 0.59, blue: 0.66)
        static let stateError = Color(red: 0.88, green: 0.31, blue: 0.29)
        static let noticeWarn = Color(red: 0.86, green: 0.58, blue: 0.10)
        static let noticeError = Color(red: 0.82, green: 0.26, blue: 0.22)
    }

    static func tint(for state: ChargeState) -> Color {
        switch state {
        case .holdingAtLimit:
            return Palette.stateHolding
        case .charging, .temporaryOverride:
            return Palette.stateCharging
        case .waitingForRecharge:
            return Palette.stateWaiting
        case .suspended:
            return Palette.stateSuspended
        case .errorReadOnly:
            return Palette.stateError
        }
    }

    static func tint(for support: CapabilitySupport) -> Color {
        switch support {
        case .supported:
            return Palette.stateHolding
        case .unsupported:
            return Palette.stateError
        case .experimental:
            return Palette.noticeWarn
        case .readOnlyFallback:
            return Palette.stateWaiting
        }
    }
}

struct InlineNotice: View {
    enum Tone {
        case warn
        case info
        case error

        var symbol: String {
            switch self {
            case .warn: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .warn: return CellCapTheme.Palette.noticeWarn
            case .info: return Color.secondary
            case .error: return CellCapTheme.Palette.noticeError
            }
        }
    }

    let title: String
    let detail: String?
    var tone: Tone = .warn

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tone.symbol)
                .foregroundStyle(tone.tint)
                .font(.callout)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: CellCapTheme.Corner.medium, style: .continuous)
                .fill(tone.tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CellCapTheme.Corner.medium, style: .continuous)
                .stroke(tone.tint.opacity(0.30), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}
