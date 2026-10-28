import LazyCustomLayout
import SwiftUI

/// A deliberately "heavy" card — around thirty subviews, with a body text
/// and tag row whose lengths vary by `index` — used to stress-test whether
/// `LazyGrid`'s create/destroy-per-item windowing stays smooth once a cell
/// costs more than a plain `RoundedRectangle`.
struct HeavyGridCell: View {
    var index: Int

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo]
    private static let statIcons = ["heart.fill", "bubble.left.fill", "arrowshape.turn.up.right.fill"]

    private var color: Color { Self.palette[index % Self.palette.count] }
    private var tagCount: Int { 2 + index % 4 }
    private var bodyLineLimit: Int { 1 + index % 4 }
    private var paragraph: String { LoremText.paragraphs[index % LoremText.paragraphs.count] }
    private var filledStarCount: Int { 1 + index % 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text("Post #\(index)")
                .font(.headline)

            Text(paragraph)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(bodyLineLimit)

            tagRow

            Divider()

            statsFooter

            ratingRow

            ProgressView(value: Double(filledStarCount), total: 5)
                .tint(color)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.08))
        }
        .onAppear { CellAppearPerfLog.shared.recordAppear() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String(format: "U%02d", index % 100))
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(color)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("User \(index % 100)")
                    .font(.footnote)
                    .bold()

                Text("\(index % 24)h ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        }
    }

    private var tags: [String] {
        paragraph
            .split(separator: " ")
            .prefix(tagCount)
            .map { "#" + $0.lowercased().filter(\.isLetter) }
    }

    private var tagRow: some View {
        LazyFlow(tags, spacing: 6, lineSpacing: 6, estimatedItemLength: 60) { tag in
            Text(tag)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.15), in: Capsule())
        }
        .lazyLayoutSizing(.fitToContent)
    }

    private var statsFooter: some View {
        HStack(spacing: 14) {
            ForEach(Array(Self.statIcons.enumerated()), id: \.offset) { offset, icon in
                Label("\((index * 37 + offset * 13) % 999 + 1)", systemImage: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ratingRow: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { star in
                Image(systemName: star < filledStarCount ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
    }
}

#Preview {
    HeavyGridCell(index: 3)
        .padding()
}
