// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Report characteristics share UUIDs; their concrete input roles must remain distinct.
public enum HIDInputEndpoint: String, Hashable, Sendable {
    case mouseReport, mouseBoot, keyboardReport, keyboardBoot
}

/// Actual transport readiness, including suspend/protocol state and a connection epoch.
/// UUID alone is insufficient: the same host may reconnect between two timer ticks.
public struct HIDPeerRegistry: Sendable {
    private struct Peer: Equatable, Sendable {
        var endpoints: Set<HIDInputEndpoint> = []
        var suspended = false
        var mode: UInt8 = 1
    }
    private var peers: [UUID: Peer] = [:]
    public private(set) var epoch: UInt64 = 0
    public init() {}
    public var mouseReceivers: Set<UUID> { ready(report: .mouseReport, boot: .mouseBoot) }
    public var keyboardReceivers: Set<UUID> { ready(report: .keyboardReport, boot: .keyboardBoot) }
    public func protocolMode(for peer: UUID) -> UInt8 { peers[peer]?.mode ?? 1 }
    public mutating func subscribe(_ endpoint: HIDInputEndpoint, peer: UUID) {
        mutate(peer) { $0.endpoints.insert(endpoint) }
    }
    public mutating func unsubscribe(_ endpoint: HIDInputEndpoint, peer: UUID) {
        guard peers[peer] != nil else { return }
        mutate(peer) { $0.endpoints.remove(endpoint) }
    }
    public mutating func setSuspended(_ suspended: Bool, peer: UUID) {
        mutate(peer) { $0.suspended = suspended }
    }
    @discardableResult public mutating func setProtocol(_ mode: UInt8, peer: UUID) -> Bool {
        guard mode <= 1 else { return false }
        mutate(peer) { $0.mode = mode }; return true
    }
    public mutating func forget(_ peer: UUID) {
        if peers.removeValue(forKey: peer) != nil { epoch &+= 1 }
    }
    public mutating func reset() { peers.removeAll(); epoch &+= 1 }
    private mutating func mutate(_ id: UUID, _ body: (inout Peer) -> Void) {
        let old = peers[id]; var value = old ?? Peer(); body(&value)
        if old != value { peers[id] = value; epoch &+= 1 }
    }
    private func ready(report: HIDInputEndpoint, boot: HIDInputEndpoint) -> Set<UUID> {
        Set(peers.compactMap { id, peer in
            !peer.suspended && peer.endpoints.contains(peer.mode == 0 ? boot : report) ? id : nil
        })
    }
}
