import LazyCustomLayout
import SwiftUI

/// Same engine, same gestures, just the horizontal axis — proves the engine
/// isn't hardwired to vertical scrolling.
struct HorizontalScrollExample: View {
    private static let cardCount = 20
    private static let cardWidth: CGFloat = 160

    var body: some View {
        AnchoredScrollView(axis: .horizontal) {
            HStack(spacing: 0) {
                ForEach(0..<Self.cardCount, id: \.self) { index in
                    Card(index: index)
                        .frame(width: Self.cardWidth)
                }
            }
        }
        .navigationTitle("Horizontal Scroll")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HorizontalScrollExample()
    }
}
