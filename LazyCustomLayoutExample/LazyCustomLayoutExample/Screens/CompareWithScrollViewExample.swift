import LazyCustomLayout
import SwiftUI

/// The engine and a real `ScrollView`, scrolling identical content stacked
/// top and bottom, so a fling or a drag past the edge can be tried on both
/// back to back.
struct CompareWithScrollViewExample: View {
    var body: some View {
        VStack(spacing: 0) {
            Header("LazyCustomLayout engine", color: .blue)
            AnchoredScrollView {
                TextColumn()
            }

            Divider()

            Header("ScrollView (UIScrollView)", color: .green)
            ScrollView {
                TextColumn()
            }
        }
        .navigationTitle("Compare with ScrollView")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct Header: View {
        var text: String
        var color: Color

        init(_ text: String, color: Color) {
            self.text = text
            self.color = color
        }

        var body: some View {
            Text(text)
                .font(.caption)
                .bold()
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(color.opacity(0.15))
        }
    }
}

#Preview {
    NavigationStack {
        CompareWithScrollViewExample()
    }
}
