import SwiftUI

/// Entry point, listing one screen per capability the engine demonstrates on
/// its own. Add a new entry here as later phases (anchor model, lazy
/// layouts) land.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Custom examples") {
                    NavigationLink("Calculator") {
                        CalculatorExample()
                    }
                    NavigationLink("Collage (Custom Layout)") {
                        CollageExample()
                    }
                }

                Section("Built-in Lazy Layouts") {
                    NavigationLink("Masonry") {
                        MasonryExample()
                    }
                    NavigationLink("Flow") {
                        FlowExample()
                    }
                    NavigationLink("Grid") {
                        GridExample()
                    }
                    NavigationLink("Heavy Grid (cell reuse)") {
                        HeavyGridExample()
                    }
                }

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
            }
            .navigationTitle("LazyCustomLayout")
        }
    }
}

#Preview {
    ContentView()
}
