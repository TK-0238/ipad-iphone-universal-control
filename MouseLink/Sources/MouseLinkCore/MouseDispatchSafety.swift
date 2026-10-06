// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Evaluated at the actual write boundary, including write-ready callbacks (not just on a timer).
public enum MouseDispatchSafety {
    public enum Decision: Equatable, Sendable { case send, release, disconnect, discard }
    public static func decide(_ item: PendingMouseFrame, at time: TimeInterval, active: Bool,
                              foreground: Bool, locked: Bool, sameConnection: Bool) -> Decision {
        guard sameConnection else { return .discard }
        guard time.isFinite, time >= item.queuedAt else { return .disconnect }
        let age=time-item.queuedAt
        if active && (!foreground || age > 0.5 || (!locked && item.frame != .zero)) { return .release }
        if !active && (age > 0.7 || item.frame != .zero) { return .disconnect }
        return .send
    }
}
