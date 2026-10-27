import LazyCustomLayout
import SwiftUI

/// Proves out `LazyStack` (`LazyAnchoredScroll` + `StackLayout`): 2,000 rows
/// of varying height, scrolled by the engine. `maxLoadedItems` caps how many
/// rows are ever instantiated at once, regardless of how much buffer
/// distance would otherwise call for.
struct TableExample: View {
    private static let rowCount = 2000

    var body: some View {
        LazyStack(0..<Self.rowCount, spacing: 1, estimatedItemLength: 60, maxLoadedItems: 30) { index in
            LazyTableRow(index: index)
        }
        .navigationTitle("Table")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LazyTableRow: View {
    var index: Int

    private var height: CGFloat {
        40 + CGFloat(index % 5) * 20
    }

    var body: some View {
        HStack {
            Text("Row \(index)")
                .font(.headline)

            Spacer()

            Text("\(Int(height))pt")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(index.isMultiple(of: 2) ? Color.gray.opacity(0.08) : Color.clear)
    }
}

#Preview {
    NavigationStack {
        TableExample()
    }
}
