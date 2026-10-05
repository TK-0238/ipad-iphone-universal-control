// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public enum DevicePlacement: String, CaseIterable, Sendable {
    case left, right
    public var title: String { self == .left ? "左" : "右" }
    public var edgeDescription: String { self == .left ? "左端" : "右端" }
}
public struct EdgeHandoffContext: Equatable, Sendable {
    public let peer: String
    public let epoch: UInt64
    public let side: DevicePlacement
    public init(peer: String, epoch: UInt64, side: DevicePlacement) {
        self.peer = peer; self.epoch = epoch; self.side = side
    }
}
public struct EdgePointer: Sendable {
    public let x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    var valid: Bool {
        [x,y,width,height].allSatisfy(\.isFinite) && width >= 160 && height >= 160 &&
        x >= 0 && x <= width && y >= 0 && y <= height
    }
}

/// A deliberate, explicitly armed, one-shot foreground handoff. Never persists authorization.
/// This recognizes a gesture inside our scene, not the iPhone's cursor or the iPad desktop.
public struct EdgeHandoffGate: Sendable {
    public private(set) var isArmed = false
    public private(set) var progress: Double = 0
    private var context: EdgeHandoffContext?
    private var interiorSeen = false
    private var since: TimeInterval?
    private var lastTime: TimeInterval?
    private var size: (Double, Double)?
    public init() {}
    public mutating func arm(context: EdgeHandoffContext) {
        disarm()
        guard !context.peer.isEmpty else { return }
        self.context = context; isArmed = true
    }
    public mutating func disarm() {
        isArmed = false; context = nil; lastTime = nil; size = nil; resetVisit()
    }
    private mutating func resetVisit() { interiorSeen = false; since = nil; progress = 0 }
    @discardableResult public mutating func observe(_ pointer: EdgePointer?, context: EdgeHandoffContext?,
        allowed: Bool, buttonsReleased: Bool, at time: TimeInterval) -> Bool {
        guard isArmed else { return false }
        guard allowed, context == self.context, let context,
              time.isFinite, time >= 0, lastTime.map({time >= $0}) ?? true else { disarm(); return false }
        let gap = lastTime.map { time - $0 > 0.25 } ?? false
        lastTime = time
        guard !gap else { resetVisit(); return false }
        guard let p = pointer, p.valid, buttonsReleased else { resetVisit(); return false }
        if let size, size.0 != p.width || size.1 != p.height {
            self.size = (p.width,p.height); resetVisit(); return false
        }
        size = (p.width,p.height)
        guard p.y >= 48 && p.y <= p.height - 48 else { resetVisit(); return false }
        let atEdge = context.side == .left ? p.x <= 24 : p.x >= p.width - 24
        guard atEdge else {
            since = nil; progress = 0
            // Seeing the opposite edge does not count as an intentional interior visit.
            interiorSeen = p.x > 24 && p.x < p.width - 24
            return false
        }
        guard interiorSeen else { return false }
        if since == nil { since = time }
        let elapsed = time - (since ?? time)
        progress = min(1, max(0, elapsed / 0.7))
        if elapsed >= 0.7 { disarm(); return true }
        return false
    }
}
