import LazyCustomLayout
import SwiftUI

private let gridSpacing: Double = 12

/// Proves out `LazyGrid`'s auto-placement, track sizing, and packing
/// modes — a segmented control switches between a few representative
/// layouts instead of picking just one.
struct GridExample: View {
    @State private var sample: GridSample = .columns

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sample", selection: $sample) {
                ForEach(GridSample.allCases, id: \.self) { sample in
                    Text(sample.title).tag(sample)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            sample.content
                .padding(.horizontal, gridSpacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("Grid")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum GridSample: CaseIterable {
    case columns
    case rows
    case sizing
    case spans

    var title: String {
        switch self {
        case .columns: "Columns"
        case .rows: "Rows"
        case .sizing: "Sizing"
        case .spans: "Spans"
        }
    }

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .green, .cyan, .indigo]
    private static let sizingTracks: [GridTrack] = [.px(70), .fr(1), .px(70), .fr(2)]

    @ViewBuilder
    var content: some View {
        switch self {
        case .columns:
            LazyGrid(columns: 3, spacing: gridSpacing, estimatedRowLength: 130) {
                ForEach(0..<300) { index in
                    GridTile(color: Self.palette[index % Self.palette.count], label: "\(index)")
                        .aspectRatio(1, contentMode: .fit)
                }
            }

        case .rows:
            // The auto-sized axis here is width (columns grow as the grid
            // scrolls horizontally) — each tile needs an explicit width of
            // its own, varied here so the snake-order placement across
            // rows is easy to follow as the numbers climb from 1 to 20.
            LazyGrid(rows: 3, spacing: gridSpacing) {
                ForEach(1...20, id: \.self) { number in
                    GridTile(color: Self.palette[number % Self.palette.count], label: "\(number)")
                        .frame(width: 56 + CGFloat(number % 3) * 24)
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)

        case .sizing:
            // Columns alternate `.px` (a fixed width) and `.fr` (a share of
            // whatever space is left) — the caption below spells out which
            // is which.
            VStack(spacing: gridSpacing) {
                LazyGrid(columns: Self.sizingTracks, spacing: gridSpacing) {
                    ForEach(0..<12) { index in
                        let track = Self.sizingTracks[index % Self.sizingTracks.count]

                        GridTile(color: Self.palette[index % Self.palette.count], label: track.label)
                            .frame(height: 90)
                    }
                }
                .frame(height: 3 * 90 + 2 * gridSpacing)

                Text("Px — fixed width · Fr — shares what's left over")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, gridSpacing)

        case .spans:
            // Only the single-row-span tiles need an explicit height — a
            // multi-row span is always proposed a concrete height (the sum
            // of its spanned rows), never left to size itself.
            LazyGrid(columns: [.fr(1), .px(150), .fr(2)], spacing: gridSpacing, packing: .dense, estimatedRowLength: 90) {
                GridTile(color: Self.palette[0], label: "2×1").frame(height: 90).gridSpan(column: 2)
                GridTile(color: Self.palette[1], label: "1×2").gridSpan(row: 2)
                GridTile(color: Self.palette[2], label: "1×1").frame(height: 90)
                GridTile(color: Self.palette[3], label: "1×1").frame(height: 90)
                GridTile(color: Self.palette[4], label: "2×3").gridSpan(column: 2, row: 3)
                GridTile(color: Self.palette[5], label: "1×1").frame(height: 90)
                GridTile(color: Self.palette[6], label: "1×2").gridSpan(row: 2)
            }
        }
    }
}

private extension GridTrack {
    var label: String {
        switch self {
        case .px(let length): "Px(\(Int(length)))"
        case .fr(let weight): "Fr(\(Int(weight)))"
        }
    }
}

private struct GridTile: View {
    var color: Color
    var label: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(color.opacity(0.22))
            .overlay {
                if let label {
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(color)
                }
            }
    }
}

#Preview {
    NavigationStack {
        GridExample()
    }
}
