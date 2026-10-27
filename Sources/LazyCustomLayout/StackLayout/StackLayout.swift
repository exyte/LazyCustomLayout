import SwiftUI

/// The simplest `StreamingLayout`: items placed one after another along the
/// scroll axis with fixed spacing between them, like a single-column table.
/// Proposes the full cross-axis length and lets content size itself freely
/// along the scroll axis.
public struct StackLayout: StreamingLayout {
    public var spacing: Double

    public init(spacing: Double = 0) {
        self.spacing = spacing
    }

    public func proposedSize(context: StreamingLayoutContext, cache: inout Void) -> ProposedViewSize {
        context.fullCrossAxisProposal
    }

    public func place(size: CGSize, context: StreamingLayoutContext, cache: inout Void) -> CGRect {
        switch context.axis {
        case .vertical:
            let origin = switch context.direction {
            case .forward: context.neighborFrame.map { $0.maxY + spacing } ?? 0
            case .backward: (context.neighborFrame.map { $0.minY - spacing } ?? 0) - size.height
            }
            return CGRect(origin: CGPoint(x: 0, y: origin), size: size)
        case .horizontal:
            let origin = switch context.direction {
            case .forward: context.neighborFrame.map { $0.maxX + spacing } ?? 0
            case .backward: (context.neighborFrame.map { $0.minX - spacing } ?? 0) - size.width
            }
            return CGRect(origin: CGPoint(x: origin, y: 0), size: size)
        }
    }
}
