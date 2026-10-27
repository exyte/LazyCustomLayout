import Foundation
import Observation

/// Basic left-to-right (no operator precedence) calculator logic, the same
/// way the stock iOS Calculator behaves — not the point of this example,
/// just enough for the buttons to do something real.
@Observable
final class CalculatorModel {
    private(set) var display = "0"

    private var accumulator: Double = 0
    private var pendingOperator: CalculatorButton?
    private var isEnteringNewNumber = true
    private var currentInput = "0"

    func press(_ button: CalculatorButton) {
        switch button {
        case .digit(let digit): enterDigit(digit)
        case .dot: enterDot()
        case .clear: clear()
        case .plusMinus: toggleSign()
        case .percent: applyPercent()
        case .divide, .multiply, .subtract, .add: setPendingOperator(button)
        case .equals: evaluate()
        }

        display = currentInput
    }

    private func enterDigit(_ digit: Int) {
        if isEnteringNewNumber {
            currentInput = "\(digit)"
            isEnteringNewNumber = false
        } else {
            currentInput += "\(digit)"
        }
    }

    private func enterDot() {
        if isEnteringNewNumber {
            currentInput = "0."
            isEnteringNewNumber = false
        } else if !currentInput.contains(".") {
            currentInput += "."
        }
    }

    private func clear() {
        accumulator = 0
        pendingOperator = nil
        currentInput = "0"
        isEnteringNewNumber = true
    }

    private func toggleSign() {
        guard let value = Double(currentInput) else { return }
        currentInput = Self.format(-value)
    }

    private func applyPercent() {
        guard let value = Double(currentInput) else { return }
        currentInput = Self.format(value / 100)
    }

    private func setPendingOperator(_ button: CalculatorButton) {
        if !isEnteringNewNumber || pendingOperator == nil {
            evaluatePending()
        }

        pendingOperator = button
        isEnteringNewNumber = true
    }

    private func evaluate() {
        evaluatePending()
        pendingOperator = nil
        isEnteringNewNumber = true
    }

    private func evaluatePending() {
        guard let pendingOperator, let value = Double(currentInput) else {
            accumulator = Double(currentInput) ?? accumulator
            return
        }

        switch pendingOperator {
        case .add: accumulator += value
        case .subtract: accumulator -= value
        case .multiply: accumulator *= value
        case .divide: accumulator = value == 0 ? 0 : accumulator / value
        default: break
        }

        currentInput = Self.format(accumulator)
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite else { return "Error" }

        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int(value))
        }

        return String(format: "%.6g", value)
    }
}
