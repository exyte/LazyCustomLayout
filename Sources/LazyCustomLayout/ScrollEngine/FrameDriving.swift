/// A source of per-frame callbacks, used by `ScrollEngine` to animate flings
/// and spring-backs without owning any UIKit/QuartzCore dependency itself.
///
/// The real implementation (`FrameClock`, in the `LazyCustomLayout` target) wraps
/// `CADisplayLink`. Tests substitute a fake that's driven manually, one frame
/// at a time, so `ScrollEngine`'s logic can be verified without a run loop.
@MainActor
public protocol FrameDriving: AnyObject {
    /// `timestamp`: the frame's target presentation time, seconds, in whatever
    /// domain the implementation uses — `ScrollEngine` only ever looks at
    /// `deltaTime` between consecutive calls, never at the absolute value.
    /// `deltaTime`: elapsed time since the previous frame, seconds.
    typealias Callback = (_ timestamp: Double, _ deltaTime: Double) -> Void

    var callback: Callback? { get set }
    var isRunning: Bool { get }

    /// Starts firing `callback` every frame. No-op if already running.
    func start()

    /// Stops firing `callback`.
    func stop()
}
