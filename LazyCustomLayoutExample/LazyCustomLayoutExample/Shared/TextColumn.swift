import SwiftUI

/// Shared content for the vertical/comparison screens, so the engine-driven
/// and plain-`ScrollView` sides are scrolling identical content.
struct TextColumn: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(LoremText.paragraphs.indices, id: \.self) { index in
                Text(LoremText.paragraphs[index])
            }
        }
        .padding()
    }
}
