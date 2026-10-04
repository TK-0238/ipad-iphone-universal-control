// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// A requested UIKit pointer lock is not permission to forward input.
/// Input starts only after UIKit's actual lock is observed. Unlocking requires a new start.
public struct PointerLockGate: Sendable {
    private var requestedAt: TimeInterval?
    public private(set) var canForward = false
    public init() {}
    public mutating func request(at time: TimeInterval) {
        stop()
        if time.isFinite { requestedAt = time }
    }
    /// Returns true when the active request must be stopped.
    public mutating func observe(locked: Bool, at time: TimeInterval) -> Bool {
        guard let start = requestedAt else { return false }
        guard time.isFinite, time >= start else { stop(); return true }
        if locked { canForward = true; return false }
        if canForward || time - start > 1 { stop(); return true }
        return false
    }
    public mutating func stop() { requestedAt = nil; canForward = false }
}
