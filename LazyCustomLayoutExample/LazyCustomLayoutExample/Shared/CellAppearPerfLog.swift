import Foundation
import QuartzCore

/// Temporary per-second console logging of cell `onAppear` calls, gated by
/// `LCL_PERF_LOG=1` — pairs with the package's own `ScrollPerfLog` to show
/// how many cells get created (vs. reused) while scrolling. Not meant to
/// ship; remove once the heavy-cell scrolling performance work is done.
@MainActor
final class CellAppearPerfLog {
    static let shared = CellAppearPerfLog()
    static let isEnabled = ProcessInfo.processInfo.environment["LCL_PERF_LOG"] == "1"

    private var appearCount = 0
    private var windowStart = CACurrentMediaTime()

    func recordAppear() {
        guard Self.isEnabled else { return }

        appearCount += 1

        let now = CACurrentMediaTime()
        guard now - windowStart >= 1 else { return }

        print("[LCL perf] cellAppears=\(appearCount)")
        appearCount = 0
        windowStart = now
    }
}
