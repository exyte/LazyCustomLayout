import Foundation
import QuartzCore
import SwiftUI

/// Temporary per-second console logging, gated by `LCL_PERF_LOG=1` — a tool
/// to compare before/after numbers while fixing the heavy-cell scrolling
/// performance issue. Not meant to ship; remove once that work is done.
@MainActor
final class ScrollPerfLog {
    static let shared = ScrollPerfLog()
    static let isEnabled = ProcessInfo.processInfo.environment["LCL_PERF_LOG"] == "1"

    private var frameCount = 0
    private var hitchCount = 0
    private var windowWalkCount = 0
    private var windowWalkTotalMs: Double = 0
    private var bodyPassCount = 0
    private var windowStart = CACurrentMediaTime()

    private var lastAnchorID: Int?
    private var lastAnchorOffset: Double?
    private var lastWindowIndexCount: Int?
    private var lastPoolSlotCount: Int?
    private var lastPoolActiveCount: Int?
    private var lastForwardSlack: Double??
    private var lastBackwardSlack: Double??
    private var lastViewportSize: CGSize?
    private var lastSampleFrame: CGRect?
    private var lastSampleProposal: ProposedViewSize?

    func recordFrame(isHitch: Bool) {
        guard Self.isEnabled else { return }

        frameCount += 1
        if isHitch { hitchCount += 1 }

        flushIfNeeded()
    }

    func recordWindowWalk(durationMs: Double) {
        guard Self.isEnabled else { return }

        windowWalkCount += 1
        windowWalkTotalMs += durationMs
    }

    func recordBodyPass() {
        guard Self.isEnabled else { return }

        bodyPassCount += 1
    }

    /// Debug-only snapshot of where the anchor and pool are right now —
    /// temporary diagnostic for the "grid goes blank mid-fling" repro, not
    /// part of the before/after perf comparison.
    func recordState(
        anchorID: Int,
        anchorOffset: Double,
        windowIndexCount: Int,
        poolSlotCount: Int,
        poolActiveCount: Int,
        forwardSlack: Double?,
        backwardSlack: Double?,
        viewportSize: CGSize,
        sampleFrame: CGRect?,
        sampleProposal: ProposedViewSize?
    ) {
        guard Self.isEnabled else { return }

        lastAnchorID = anchorID
        lastAnchorOffset = anchorOffset
        lastWindowIndexCount = windowIndexCount
        lastPoolSlotCount = poolSlotCount
        lastPoolActiveCount = poolActiveCount
        lastForwardSlack = forwardSlack
        lastBackwardSlack = backwardSlack
        lastViewportSize = viewportSize
        lastSampleFrame = sampleFrame
        lastSampleProposal = sampleProposal
    }

    private func flushIfNeeded() {
        let now = CACurrentMediaTime()
        guard now - windowStart >= 1 else { return }

        let walkMs = String(format: "%.2f", windowWalkTotalMs)
        let offset = lastAnchorOffset.map { String(format: "%.1f", $0) } ?? "nil"
        print("[LCL perf] frames=\(frameCount) hitches=\(hitchCount) walks=\(windowWalkCount) walkMs=\(walkMs) bodyPasses=\(bodyPassCount) anchorID=\(lastAnchorID.map(String.init) ?? "nil") anchorOffset=\(offset) windowIndices=\(lastWindowIndexCount.map(String.init) ?? "nil") poolSlots=\(lastPoolSlotCount.map(String.init) ?? "nil") poolActive=\(lastPoolActiveCount.map(String.init) ?? "nil") fwdSlack=\(String(describing: lastForwardSlack)) bwdSlack=\(String(describing: lastBackwardSlack)) viewport=\(String(describing: lastViewportSize)) sampleFrame=\(String(describing: lastSampleFrame)) sampleProposal=\(String(describing: lastSampleProposal))")

        frameCount = 0
        hitchCount = 0
        windowWalkCount = 0
        windowWalkTotalMs = 0
        bodyPassCount = 0
        windowStart = now
    }
}
