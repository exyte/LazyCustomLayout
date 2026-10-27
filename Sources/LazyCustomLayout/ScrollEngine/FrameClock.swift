import QuartzCore
import UIKit

/// Drives per-frame callbacks using `CADisplayLink`, running only while
/// explicitly started — e.g. during a fling or a spring-back animation — not
/// continuously for the lifetime of the scroll view.
///
/// Requests up to 120Hz via `preferredFrameRateRange` on ProMotion displays.
/// The host app needs `CADisableMinimumFrameDurationOnPhone = YES` in its
/// Info.plist for this to actually reach 120Hz on iPhone.
@MainActor
public final class FrameClock: NSObject, FrameDriving {

    public var callback: Callback?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: Double?

    public override init() {
        super.init()
    }

    isolated deinit {
        displayLink?.invalidate()
    }

    public var isRunning: Bool { displayLink != nil }

    /// Starts firing `callback` every frame. No-op if already running.
    public func start() {
        guard displayLink == nil else { return }

        lastTimestamp = nil

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Stops firing `callback`.
    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let timestamp = link.targetTimestamp
        let delta = lastTimestamp.map { timestamp - $0 } ?? (1.0 / 60.0)

        lastTimestamp = timestamp
        callback?(timestamp, delta)
    }
}
