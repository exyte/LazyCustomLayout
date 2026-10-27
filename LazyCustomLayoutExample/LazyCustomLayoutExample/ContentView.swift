import SwiftUI

/// Entry point, listing one screen per capability the engine demonstrates on
/// its own. Add a new entry here as later phases (anchor model, lazy
/// layouts) land.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Anchored Scroll") {
                    NavigationLink("Vertical Scroll") {
                        VerticalScrollExample()
                    }
                    NavigationLink("Horizontal Scroll") {
                        HorizontalScrollExample()
                    }
                    NavigationLink("Compare with ScrollView") {
                        CompareWithScrollViewExample()
                    }
                    NavigationLink("Lazy Table") {
                        TableExample()
                    }
                }

                Section("Lazy Layouts") {
                    NavigationLink("Masonry") {
                        MasonryExample()
                    }
                    NavigationLink("Flow") {
                        FlowExample()
                    }
                    NavigationLink("Grid") {
                        GridExample()
                    }
                    NavigationLink("Calculator") {
                        CalculatorExample()
                    }
                }
            }
            .navigationTitle("LazyCustomLayout")
        }
    }
}

#Preview {
    ContentView()
}
