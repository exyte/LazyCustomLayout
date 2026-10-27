import LazyCustomLayout
import SwiftUI

/// The simplest possible test of the engine: some text, scrolled vertically.
/// No `ScrollView` involved at all.
struct VerticalScrollExample: View {
    var body: some View {
        AnchoredScrollView {
            TextColumn()
        }
        .navigationTitle("Vertical Scroll")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        VerticalScrollExample()
    }
}
