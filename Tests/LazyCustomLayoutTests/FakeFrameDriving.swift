@testable import LazyCustomLayout

/// A `FrameDriving` test double that's driven manually, one frame at a time,
/// so `ScrollEngine`'s animation logic can be verified without a real run
/// loop or `CADisplayLink`.
@MainActor
final class FakeFrameDriving: FrameDriving {
    var callback: Callback?
    private(set) var isRunning = false
    private(set) var startCount = 0

    func start() {
        guard !isRunning else { return }

        isRunning = true
        startCount += 1
    }

    func stop() {
        isRunning = false
    }

    /// Simulates one frame, `deltaTime` seconds after the previous one.
    func tick(deltaTime: Double) {
        callback?(0, deltaTime)
    }

    /// Simulates `count` frames of `deltaTime` seconds each, stopping early if
    /// the engine stops the clock partway through.
    func run(frames count: Int, deltaTime: Double) {
        for _ in 0..<count {
            guard isRunning else { return }
            tick(deltaTime: deltaTime)
        }
    }
}
