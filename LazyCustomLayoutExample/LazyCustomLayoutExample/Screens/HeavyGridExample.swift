import LazyCustomLayout
import SwiftUI

private let gridSpacing: Double = 12

/// Each cell is ~30 subviews with content-driven height, to stress-test
/// whether `LazyAnchoredScroll`'s default cell reuse stays smooth once a
/// cell costs more than a plain `RoundedRectangle`. `LazyDataGrid`, not
/// `LazyGrid`, since reuse needs a plain content closure, not
/// `Group(subviews:)`'s own per-item identity — see `LazyDataGrid`'s doc
/// comment.
struct HeavyGridExample: View {
    var body: some View {
        LazyDataGrid(0..<2000, columns: 2, spacing: gridSpacing, estimatedRowLength: 260) { index in
            HeavyGridCell(index: index)
        }
        .cellReuse(false) // TEMP: isolating whether the freeze is reuse or the engine-caching changes
        .padding(.horizontal, gridSpacing)
        .navigationTitle("Heavy Grid")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HeavyGridExample()
    }
}
