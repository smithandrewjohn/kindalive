// Clock — injectable time control. Ports kindalive/engine/clock.py.
//
// Production code uses RealClock. Tests (and the app's simulation loop,
// mirroring the web UI's ManualClock + scaled-dt pattern) use ManualClock
// to advance time explicitly and deterministically.

import Foundation

public protocol Clock: AnyObject {
    /// Current time in seconds (monotonic).
    func now() -> Double
}

/// Uses real monotonic time.
public final class RealClock: Clock {
    public init() {}

    public func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}

/// Test/simulation clock that only advances when told to.
public final class ManualClock: Clock {
    private var time: Double

    public init(start: Double = 0.0) {
        self.time = start
    }

    public func now() -> Double {
        time
    }

    public func advance(seconds: Double = 0.0, minutes: Double = 0.0, hours: Double = 0.0) {
        time += seconds + minutes * 60.0 + hours * 3600.0
    }
}
