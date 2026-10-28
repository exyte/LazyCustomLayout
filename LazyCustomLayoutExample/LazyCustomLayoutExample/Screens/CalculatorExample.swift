import LazyCustomLayout
import SwiftUI

/// Uses `LazyGrid(columns:rows:)` — its fixed, non-scrolling mode, since
/// the whole keypad is always on screen at once, nothing to stream. Every
/// button keeps the same `CalculatorButton` identity across both modes (the
/// `ForEach` below is keyed on it, and `LazyGrid` preserves that identity
/// through to the subviews it auto-places), so switching modes animates each
/// one to its new slot instead of cross-dissolving a totally different view
/// tree.
struct CalculatorExample: View {
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @State private var mode: CalculatorMode = .system
    @State private var model = CalculatorModel()

    private let spacing: CGFloat = 16
    private let minKeypadHeight: CGFloat = 5 * 44 + 4 * 12
    private let displayHeightRange: ClosedRange<CGFloat> = 36...76

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { proxy in
            // The keypad has priority: the display only gets what's left
            // after the keypad's minimum height, shrinking down to its floor.
            let leftover = proxy.size.height - minKeypadHeight - spacing * 2
            let displayHeight = min(max(leftover, displayHeightRange.lowerBound), displayHeightRange.upperBound)

            VStack(spacing: spacing) {
                if !isCompactHeight {
                    modePicker
                        .padding(.horizontal)
                }

                Spacer(minLength: 0)

                Text(model.display)
                    .font(.system(size: displayHeight * 0.84, weight: .thin))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: displayHeight)
                    .padding(.horizontal)

                keypad
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
        .background(Color.black)
        .navigationTitle("Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isCompactHeight {
                ToolbarItem(placement: .principal) {
                    modePicker
                        .frame(width: 260)
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode.animation(.spring(response: 0.45, dampingFraction: 0.82))) {
            ForEach(CalculatorMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .tint(.orange)
        .colorScheme(.dark)
    }

    private var keypad: some View {
        LazyGrid(columns: mode.columnCount, rows: mode.rowCount, spacing: 12) {
            ForEach(mode.orderedButtons, id: \.self) { button in
                let span = mode.span(for: button)

                CalculatorButtonView(button: button) {
                    model.press(button)
                }
                .gridSpan(column: span.column, row: span.row)
            }
        }
    }
}

private struct CalculatorButtonView: View {
    var button: CalculatorButton
    var action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            Button(action: action) {
                Text(button.label)
                    .font(.system(size: 32))
                    .foregroundStyle(button.style.textColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(button.style.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: min(proxy.size.width, proxy.size.height) / 2, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack {
        CalculatorExample()
    }
}
