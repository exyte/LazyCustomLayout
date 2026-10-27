import Foundation

/// Physics formulas that approximate `UIScrollView`'s deceleration, rubber-banding,
/// and overscroll spring-back behavior.
///
/// These are deliberately kept as pure functions over `Double` so they can be
/// unit tested without UIKit. Exact constants are tuned against a real
/// `UIScrollView` on device later (see the project plan); what's verified here
/// is that the math itself is self-consistent (continuity, monotonicity,
/// convergence), not that it matches UIKit bit-for-bit.
public enum ScrollPhysics {

    // MARK: Deceleration

    /// Mirrors `UIScrollView.DecelerationRate`: the fraction of velocity that
    /// survives each millisecond of coasting.
    public enum DecelerationRate {
        case normal
        case fast
        case custom(Double)

        var value: Double {
            switch self {
            case .normal: return 0.998
            case .fast: return 0.99
            case .custom(let value): return value
            }
        }
    }

    /// Velocity (points/second) below which a fling is considered finished.
    public static let restVelocity: Double = 10

    /// Velocity at time `t` (seconds) into a fling that started at `initialVelocity`
    /// (points/second).
    public static func velocity(
        initialVelocity: Double,
        rate: DecelerationRate,
        at t: Double
    ) -> Double {
        initialVelocity * pow(rate.value, 1000 * t)
    }

    /// Position at time `t` (seconds) into a fling that started at `initialPosition`
    /// with `initialVelocity` (points/second).
    public static func position(
        initialPosition: Double,
        initialVelocity: Double,
        rate: DecelerationRate,
        at t: Double
    ) -> Double {
        guard initialVelocity != 0 else { return initialPosition }

        let r = rate.value
        return initialPosition + initialVelocity * (pow(r, 1000 * t) - 1) / (1000 * log(r))
    }

    /// The position a fling asymptotically settles at, i.e. `position(at:)` as
    /// `t` approaches infinity. Useful for predicting where a fling will land
    /// before running it, e.g. for paging/snapping.
    public static func restingPosition(
        initialPosition: Double,
        initialVelocity: Double,
        rate: DecelerationRate
    ) -> Double {
        guard initialVelocity != 0 else { return initialPosition }

        let r = rate.value
        return initialPosition - initialVelocity / (1000 * log(r))
    }

    /// The time (seconds) at which a fling's velocity decays below `restVelocity`.
    public static func timeToRest(
        initialVelocity: Double,
        rate: DecelerationRate
    ) -> Double {
        guard abs(initialVelocity) > restVelocity else { return 0 }

        let r = rate.value
        return log(restVelocity / abs(initialVelocity)) / (1000 * log(r))
    }

    // MARK: Rubber banding

    /// `UIScrollView`'s rubber-band curve: maps an "honest" overscroll distance
    /// `x` (how far past the edge the finger has dragged) to the actual visual
    /// displacement, given the viewport dimension `d` along the scroll axis.
    /// Approaches `d` asymptotically, so content can never be dragged more than
    /// one viewport past its edge.
    public static func rubberBand(x: Double, dimension d: Double, coefficient c: Double = 0.55) -> Double {
        guard d > 0, x != 0 else { return 0 }

        return (1 - 1 / (x * c / d + 1)) * d
    }

    /// Inverse of `rubberBand(x:dimension:coefficient:)`: given a desired visual
    /// displacement, the "honest" overscroll distance that produces it. Used to
    /// convert a drag delta back into the right amount of additional honest
    /// overscroll while already rubber-banded.
    public static func inverseRubberBand(displacement y: Double, dimension d: Double, coefficient c: Double = 0.55) -> Double {
        guard d > 0, y != 0, y < d else { return .infinity }

        return (d / (1 - y / d) - d) / c
    }

    // MARK: Spring back

    /// A critically damped spring used to animate an overscrolled edge back to
    /// rest. Critically damped means it approaches the target as fast as
    /// possible without overshooting, which matches `UIScrollView`'s bounce-back.
    public struct Spring {
        public var position: Double
        public var velocity: Double
        public var target: Double
        public var stiffness: Double

        public init(position: Double, velocity: Double, target: Double, stiffness: Double = 300) {
            self.position = position
            self.velocity = velocity
            self.target = target
            self.stiffness = stiffness
        }

        /// Whether the spring has settled close enough to its target to stop animating.
        public var isAtRest: Bool {
            abs(position - target) < 0.5 && abs(velocity) < 0.5
        }

        /// Advances the spring by `dt` seconds in place.
        public mutating func step(dt: Double) {
            // Critical damping: c = 2 * sqrt(k * m), with m = 1.
            let damping = 2 * stiffness.squareRoot()
            let displacement = position - target
            let acceleration = -stiffness * displacement - damping * velocity

            velocity += acceleration * dt
            position += velocity * dt
        }
    }
}
