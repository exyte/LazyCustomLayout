import Observation
import QuartzCore

/// Wires `ScrollEngine` up to a single `offset` value for one piece of
/// content with a measured total length — the model behind
/// `AnchoredScrollView`. Internal: callers configure `AnchoredScrollView`
/// itself, never this directly.
@MainActor
@Observable
final class SingleContentScrollController: ScrollEngineDelegate {
    private(set) var offset: Double = 0

    var axis: ScrollAxis
    var viewportLength: Double = 0
    var contentLength: Double = 0

    private let engine: ScrollEngine
    private let clock = FrameClock()
    private var lastTranslation: Double = 0

    init(axis: ScrollAxis) {
        self.axis = axis
        self.engine = ScrollEngine(clock: clock)
        self.engine.delegate = self
        self.engine.onDelta = { [weak self] delta in
            self?.offset += delta
        }
    }

    func dragChanged(_ value: ScrollDragGesture.Value) {
        let translation = axis == .vertical ? value.translation.height : value.translation.width
        let delta = translation - lastTranslation
        lastTranslation = translation

        // The engine's "forward" is the direction that reveals more content,
        // i.e. increasing offset — which is the opposite of the finger's
        // on-screen translation (dragging up/left reveals content below/right).
        engine.dragChanged(delta: -delta, time: CACurrentMediaTime())
    }

    func dragEnded(_ value: ScrollDragGesture.Value) {
        lastTranslation = 0
        let velocity = axis == .vertical ? value.velocity.height : value.velocity.width
        engine.dragEnded(fallbackVelocity: -velocity)
    }

    func touchDown() {
        engine.touchDown()
    }

    // MARK: ScrollEngineDelegate

    func scrollEngineViewportLength(_ engine: ScrollEngine) -> Double {
        viewportLength
    }

    func scrollEngine(_ engine: ScrollEngine, slackInDirection direction: ScrollEngine.Direction) -> Double? {
        switch direction {
        case .forward:
            return max(contentLength - viewportLength - offset, 0)
        case .backward:
            return max(offset, 0)
        }
    }
}
