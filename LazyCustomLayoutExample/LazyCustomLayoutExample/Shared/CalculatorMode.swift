import LazyCustomLayout

/// The two arrangements `CalculatorExample` switches between. Both place all
/// 19 `CalculatorButton`s onto a `LazyGrid(columns:rows:)`, just with
/// different column counts and spans — `orderedButtons` is the order
/// `CalculatorExample`'s `ForEach` feeds the grid, which (together with each
/// button's `span`) is all `LazyGrid`'s sparse auto-placement needs to
/// reproduce either arrangement exactly, the same way a plain CSS grid with
/// no explicit `grid-column`/`grid-row` would.
enum CalculatorMode: CaseIterable {
    case system
    case alternative

    var title: String {
        switch self {
        case .system: "System"
        case .alternative: "Alternative"
        }
    }

    var columnCount: Int {
        switch self {
        case .system: 4
        case .alternative: 5
        }
    }

    var rowCount: Int { 5 }

    var orderedButtons: [CalculatorButton] {
        switch self {
        case .system: Self.systemOrder
        case .alternative: Self.alternativeOrder
        }
    }

    func span(for button: CalculatorButton) -> GridSpan {
        switch self {
        case .system: Self.systemSpans[button] ?? GridSpan()
        case .alternative: Self.alternativeSpans[button] ?? GridSpan()
        }
    }

    /// The standard iOS calculator grid: 4 columns, a wide "0" — auto-placed
    /// row by row, left to right, exactly matching the original hand-placed
    /// layout.
    private static let systemOrder: [CalculatorButton] = [
        .percent, .plusMinus, .clear, .divide,
        .digit(1), .digit(2), .digit(3), .multiply,
        .digit(4), .digit(5), .digit(6), .subtract,
        .digit(7), .digit(8), .digit(9), .add,
        .digit(0), .dot, .equals,
    ]

    private static let systemSpans: [CalculatorButton: GridSpan] = [
        .digit(0): GridSpan(column: 2, row: 1),
    ]

    /// A redesigned grid: 5 columns, a secondary-function row up top, a tall
    /// "+" spanning two rows, and a wide "=" spanning three columns.
    private static let alternativeOrder: [CalculatorButton] = [
        .percent, .plusMinus,
        .digit(1), .digit(2), .digit(3), .subtract, .clear,
        .digit(4), .digit(5), .digit(6), .add, .divide,
        .digit(7), .digit(8), .digit(9), .multiply,
        .digit(0), .dot, .equals,
    ]

    private static let alternativeSpans: [CalculatorButton: GridSpan] = [
        .percent: GridSpan(column: 3, row: 1),
        .plusMinus: GridSpan(column: 2, row: 1),
        .add: GridSpan(column: 1, row: 2),
        .equals: GridSpan(column: 3, row: 1),
    ]
}
