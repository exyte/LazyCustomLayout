@testable import LazyCustomLayout

@MainActor
final class FakeScrollEngineDelegate: ScrollEngineDelegate {
    var viewportLength: Double = 400
    var forwardEdgeDistance: Double = .infinity
    var backwardEdgeDistance: Double = .infinity

    func scrollEngineViewportLength(_ engine: ScrollEngine) -> Double {
        viewportLength
    }

    func scrollEngine(_ engine: ScrollEngine, slackInDirection direction: ScrollEngine.Direction) -> Double? {
        switch direction {
        case .forward: return forwardEdgeDistance
        case .backward: return backwardEdgeDistance
        }
    }
}
