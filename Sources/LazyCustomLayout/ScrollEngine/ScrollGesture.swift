import SwiftUI
import UIKit

/// A pan gesture, wrapped for SwiftUI, that also recognizes trackpad and
/// mouse wheel scrolling (`allowedScrollTypesMask = .all`).
///
/// Call sites get continuous `onChanged` updates while dragging and a single
/// `onEnded` when the finger lifts or the gesture is cancelled, each carrying
/// the translation and velocity converted into the local coordinate space.
public struct ScrollDragGesture: UIGestureRecognizerRepresentable {

    public struct Value {
        public var translation: CGSize
        public var velocity: CGSize
    }

    public var onChanged: (Value) -> Void
    public var onEnded: (Value) -> Void

    public init(onChanged: @escaping (Value) -> Void, onEnded: @escaping (Value) -> Void) {
        self.onChanged = onChanged
        self.onEnded = onEnded
    }

    public func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.allowedScrollTypesMask = .all
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    public func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        // Nothing to update: the recognizer's configuration doesn't depend on state.
    }

    public func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    public func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = context.converter.translation(in: .local) ?? .zero
        let velocity = context.converter.velocity(in: .local) ?? .zero
        let value = Value(
            translation: CGSize(width: translation.x, height: translation.y),
            velocity: CGSize(width: velocity.x, height: velocity.y)
        )

        switch recognizer.state {
        case .changed:
            onChanged(value)
        case .ended, .cancelled, .failed:
            onEnded(value)
        default:
            break
        }
    }

    /// Lets the pan gesture defer to the navigation stack's interactive
    /// swipe-back gesture when a drag starts near the leading screen edge.
    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Approximates the activation width of `UINavigationController`'s
        /// interactive pop gesture. This is a heuristic, not a reference to the
        /// real `interactivePopGestureRecognizer` — tighten/loosen once this is
        /// compared against it on device (see the project plan's Phase 1 checkpoint).
        static let edgeSwipeBackWidth: CGFloat = 20

        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view else { return true }

            return touch.location(in: view).x > Self.edgeSwipeBackWidth
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// A `UIGestureRecognizer` that recognizes the instant a finger touches down,
/// without waiting for a tap, long press, or any movement.
public final class TouchDownRecognizer: UIGestureRecognizer {
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        state = .began
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        state = .failed
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .failed
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .failed
    }
}

/// Wraps `TouchDownRecognizer` for SwiftUI. Fires `onTouchDown` the instant a
/// finger touches the view, before any movement is recognized — used to stop
/// a running fling or spring immediately, matching `UIScrollView`'s
/// touch-to-stop behavior, rather than waiting for a new drag to begin.
public struct ScrollTouchDownGesture: UIGestureRecognizerRepresentable {

    public var onTouchDown: () -> Void

    public init(onTouchDown: @escaping () -> Void) {
        self.onTouchDown = onTouchDown
    }

    public func makeUIGestureRecognizer(context: Context) -> TouchDownRecognizer {
        TouchDownRecognizer()
    }

    public func updateUIGestureRecognizer(_ recognizer: TouchDownRecognizer, context: Context) {
        // Nothing to update: the recognizer's configuration doesn't depend on state.
    }

    public func handleUIGestureRecognizerAction(_ recognizer: TouchDownRecognizer, context: Context) {
        if recognizer.state == .began {
            onTouchDown()
        }
    }
}
