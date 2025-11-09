import Foundation
import MultipeerConnectivity

public struct PeerDevice: Identifiable, Hashable {
    public let peerID: MCPeerID
    public var id: MCPeerID { peerID }
    public let role: ControlRole
    public let rssi: Int?

    public init(peerID: MCPeerID, role: ControlRole, rssi: Int? = nil) {
        self.peerID = peerID
        self.role = role
        self.rssi = rssi
    }
}
