import LazyCustomLayout
import SwiftUI

/// Proves out `FlowLayout`'s variable-width wrapping: a tag cloud of
/// words, each chip sized to its own text, wrapping to a new line once the
/// current one runs out of room — the thing a fixed-size flow can't do.
struct FlowExample: View {
    private static let words: [String] = LoremText.paragraphs
        .joined(separator: " ")
        .split(separator: " ")
        .map(String.init)

    var body: some View {
        LazyFlow(Self.words, spacing: 8, lineSpacing: 10, estimatedItemLength: 44) { word in
            FlowTag(word: word)
        }
        .padding(8)
        .navigationTitle("Flow")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FlowTag: View {
    var word: String

    var body: some View {
        Text(word)
            .font(.title3)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        FlowExample()
    }
}
