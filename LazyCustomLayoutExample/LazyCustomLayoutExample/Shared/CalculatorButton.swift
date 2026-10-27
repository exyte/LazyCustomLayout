import SwiftUI

/// Every button on the calculator, independent of how either mode arranges
/// them — this identity is what `CalculatorExample` keys its `ForEach` on,
/// so a button stays the same view (and animates) across a mode switch
/// instead of being destroyed and recreated.
enum CalculatorButton: Hashable {
    case digit(Int)
    case dot
    case percent
    case plusMinus
    case clear
    case divide
    case multiply
    case subtract
    case add
    case equals

    enum Style {
        case digit
        case utility
        case operation

        var backgroundColor: Color {
            switch self {
            case .digit: Color(white: 0.2)
            case .utility: Color(white: 0.7)
            case .operation: .orange
            }
        }

        var textColor: Color {
            switch self {
            case .utility: .black
            case .digit, .operation: .white
            }
        }
    }

    var label: String {
        switch self {
        case .digit(let value): "\(value)"
        case .dot: "."
        case .percent: "%"
        case .plusMinus: "±"
        case .clear: "C"
        case .divide: "÷"
        case .multiply: "×"
        case .subtract: "−"
        case .add: "+"
        case .equals: "="
        }
    }

    var style: Style {
        switch self {
        case .digit, .dot: .digit
        case .percent, .plusMinus, .clear: .utility
        case .divide, .multiply, .subtract, .add, .equals: .operation
        }
    }
}
