// SPDX-License-Identifier: AGPL-3.0-only
// MouseLink project, 2026. Shared by the native app and its real unit tests.
import Foundation

public struct MouseFrame: Equatable, Sendable {
    public let buttons: UInt8
    public let x: Int8
    public let y: Int8
    public let wheel: Int8
    public init(buttons: UInt8 = 0, x: Int8 = 0, y: Int8 = 0, wheel: Int8 = 0) {
        self.buttons = buttons & 7; self.x = x; self.y = y; self.wheel = wheel
    }
    public static let zero = MouseFrame()
    public var data: Data { Data([buttons, UInt8(bitPattern: x), UInt8(bitPattern: y), UInt8(bitPattern: wheel)]) }
}

public enum RelayFailure: Error, Equatable, LocalizedError {
    case invalidMotion, inactive, congested, stale
    public var errorDescription: String? {
        switch self {
        case .invalidMotion: return "不正なマウス入力を検出したため停止しました。"
        case .inactive: return "転送は停止しています。"
        case .congested: return "Bluetooth送信が混雑したため安全に停止しました。"
        case .stale: return "入力の遅延を検出したため安全に停止しました。"
        }
    }
}

/// Preserve fractional input and split large movement into legal relative HID reports.
/// Silently clamping every event to 127 loses motion; this implementation preserves it.
public struct MotionAccumulator: Sendable {
    private var remainderX: Double = 0
    private var remainderY: Double = 0
    private var remainderWheel: Double = 0
    public init() {}
    public mutating func add(x: Double, y: Double, wheel: Double, buttons: UInt8) throws -> [MouseFrame] {
        guard [x, y, wheel].allSatisfy({ $0.isFinite && abs($0) <= 8192 }) else { throw RelayFailure.invalidMotion }
        let sx = x + remainderX, sy = y + remainderY, sw = wheel + remainderWheel
        var ix = Int(sx), iy = Int(sy), iw = Int(sw)
        remainderX = sx - Double(ix); remainderY = sy - Double(iy); remainderWheel = sw - Double(iw)
        var result: [MouseFrame] = []
        while ix != 0 || iy != 0 || iw != 0 {
            let dx = min(127, max(-127, ix)), dy = min(127, max(-127, iy)), dw = min(127, max(-127, iw))
            result.append(MouseFrame(buttons: buttons, x: Int8(dx), y: Int8(dy), wheel: Int8(dw)))
            ix -= dx; iy -= dy; iw -= dw
        }
        return result
    }
}

public struct PendingMouseFrame: Equatable, Sendable {
    public let peer: UUID
    public let generation: UInt64
    public let frame: MouseFrame
    public let queuedAt: TimeInterval
}

/// Ordered, bounded queue. A frame is removed only AFTER the transport accepts it.
/// Stop/overflow/timeout discard motion and leave only a best-effort release.
public struct RelayBuffer: Sendable {
    public private(set) var isActive = false
    public private(set) var peer: UUID?
    public private(set) var generation: UInt64 = 0
    private var pending: [PendingMouseFrame] = []
    private let capacity: Int
    public init(capacity: Int = 128) { self.capacity = max(2, min(1024, capacity)) }
    public var next: PendingMouseFrame? { pending.first }
    public var count: Int { pending.count }
    public mutating func begin(peer: UUID, at time: TimeInterval) {
        disconnect()
        guard time.isFinite else { return }
        self.peer = peer; isActive = true
        pending = [PendingMouseFrame(peer: peer, generation: generation, frame: .zero, queuedAt: time)]
    }
    public mutating func enqueue(_ frames: [MouseFrame], at time: TimeInterval) throws {
        guard isActive, let peer else { throw RelayFailure.inactive }
        guard time.isFinite else { pause(at: 0); throw RelayFailure.invalidMotion }
        guard frames.count <= capacity - pending.count else { pause(at: time); throw RelayFailure.congested }
        pending += frames.map { PendingMouseFrame(peer: peer, generation: generation, frame: $0, queuedAt: time) }
    }
    public mutating func acceptNext() { if !pending.isEmpty { pending.removeFirst() } }
    public mutating func pause(at time: TimeInterval) {
        isActive = false; generation &+= 1; pending.removeAll(keepingCapacity: true)
        if let peer { pending.append(PendingMouseFrame(peer: peer, generation: generation, frame: .zero, queuedAt: time.isFinite ? time : 0)) }
    }
    @discardableResult public mutating func expire(at time: TimeInterval) -> Bool {
        guard isActive, let first = pending.first else { return false }
        guard time.isFinite, time >= first.queuedAt, time - first.queuedAt <= 0.5 else { pause(at: time); return true }
        return false
    }
    public mutating func disconnect() {
        isActive = false; generation &+= 1; peer = nil; pending.removeAll(keepingCapacity: true)
    }
}

public enum ReceiverPolicy {
    public static func choose(previous: UUID?, available: Set<UUID>) -> UUID? {
        if let previous { return available.contains(previous) ? previous : nil }
        return available.count == 1 ? available.first : nil
    }
    public static func canStart(foreground: Bool, mouse: Bool, selectedIsAvailable: Bool) -> Bool {
        foreground && mouse && selectedIsAvailable
    }
}
