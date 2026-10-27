import LazyCustomLayout
import SwiftUI

/// Proves out `MasonryLayout`: a 2-lane masonry grid of varying-height
/// tiles, each lane filling independently to whichever is currently
/// shortest.
struct MasonryExample: View {
    private static let itemCount = 300

    var body: some View {
        LazyMasonry(0..<Self.itemCount, lanes: 2, spacing: 8, estimatedItemLength: 160) { index in
            MasonryTile(index: index)
        }
        .padding(.horizontal, 8)
        .navigationTitle("Masonry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MasonryTile: View {
    var index: Int

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .green]

    private var height: CGFloat {
        120 + CGFloat((index * 37) % 160)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Self.palette[index % Self.palette.count].opacity(0.3))
            .frame(height: height)
            .overlay {
                Text("\(index)")
                    .font(.headline)
            }
    }
}

#Preview {
    NavigationStack {
        MasonryExample()
    }
}
