import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        HStack(spacing: 5) {
            menuBarIcon

            Text(viewModel.batteryPercentText)
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        switch viewModel.menuBarSymbolName {
        case "pause.circle", "exclamationmark.triangle.fill":
            Image(systemName: viewModel.menuBarSymbolName)
                .imageScale(.small)
                .frame(width: 18, height: 12)
        default:
            Image(nsImage: CellCapMenuBarIconImage.shared)
                .renderingMode(.template)
                .interpolation(.none)
                .frame(width: 18, height: 12)
        }
    }
}

private enum CellCapMenuBarIconImage {
    static let shared: NSImage = makeImage()

    private static func makeImage() -> NSImage {
        let size = NSSize(width: 18, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            image.isTemplate = true
            return image
        }

        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.8)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let bodyRect = CGRect(x: 1.0, y: 1.1, width: 13.0, height: 9.8)
        let capRect = CGRect(x: 14.7, y: 4.0, width: 2.3, height: 4.0)

        let bodyPath = CGPath(
            roundedRect: bodyRect,
            cornerWidth: 2.1,
            cornerHeight: 2.1,
            transform: nil
        )
        let capPath = CGPath(
            roundedRect: capRect,
            cornerWidth: 0.8,
            cornerHeight: 0.8,
            transform: nil
        )

        context.addPath(bodyPath)
        context.strokePath()

        context.addPath(capPath)
        context.strokePath()

        context.move(to: CGPoint(x: 4.0, y: 7.7))
        context.addLine(to: CGPoint(x: 11.4, y: 7.7))
        context.strokePath()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

#Preview("Menu Bar Label") {
    MenuBarLabelView(viewModel: .previewHolding())
        .padding()
}
