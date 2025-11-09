import Foundation
import Combine
import MultipeerConnectivity
import Network
import os.log
import QuartzCore

public enum SessionState {
    case idle
    case advertising
    case browsing
    case connected(peerID: MCPeerID)
    case failed(Error)
}

public final class SessionCoordinator: NSObject, ObservableObject {
    public let serviceType = "linkpad-share"
    private let peerID: MCPeerID
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var session: MCSession?
    private let log = Logger(subsystem: "jp.kawashimataiki.linkpad", category: "session")

    @Published public private(set) var state: SessionState = .idle
    @Published public private(set) var discoveredPeers: [MCPeerID] = []

    private let inputSubject = PassthroughSubject<InputEventPayload, Never>()
    public var inputEvents: AnyPublisher<InputEventPayload, Never> {
        inputSubject.eraseToAnyPublisher()
    }

    private let frameSubject = PassthroughSubject<DisplayFrame, Never>()
    public var frameEvents: AnyPublisher<DisplayFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    public override init() {
        self.peerID = MCPeerID(displayName: Host.current().localizedName ?? UUID().uuidString)
        super.init()
    }

    public func startAdvertising() {
        teardown()
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        state = .advertising
        log.debug("Start advertising")
    }

    public func startBrowsing() {
        teardown()
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        state = .browsing
        log.debug("Start browsing")
    }

    public func connect(to peer: MCPeerID) {
        guard let browser else { return }
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    public func send(event: InputEventPayload) throws {
        guard let session, !session.connectedPeers.isEmpty else { return }
        let data = try JSONEncoder().encode(event)
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    public func send(frame: DisplayFrame) throws {
        guard let session, !session.connectedPeers.isEmpty else { return }
        let data = try JSONEncoder().encode(frame)
        try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }

    public func teardown() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        session = nil
        advertiser = nil
        browser = nil
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll()
            self.state = .idle
        }
    }
}

extension SessionCoordinator: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        log.debug("Invitation from \(peerID.displayName, privacy: .public)")
        let session = MCSession(peer: self.peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        invitationHandler(true, session)
    }
}

extension SessionCoordinator: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }
}

extension SessionCoordinator: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.state = .connected(peerID: peerID)
            case .connecting:
                self.state = .browsing
            case .notConnected:
                self.state = .idle
            @unknown default:
                self.state = .idle
            }
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let event = try? JSONDecoder().decode(InputEventPayload.self, from: data) {
            if case .system(let systemEvent) = event {
                respond(to: systemEvent, from: peerID)
            }
            inputSubject.send(event)
        } else if let frame = try? JSONDecoder().decode(DisplayFrame.self, from: data) {
            frameSubject.send(frame)
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

private extension SessionCoordinator {
    func respond(to event: SystemEvent, from peerID: MCPeerID) {
        guard let session else { return }
        switch event {
        case .ping(let id, _):
            let response = InputEventPayload.system(.pong(id: id, timestamp: CACurrentMediaTime()))
            guard let data = try? JSONEncoder().encode(response) else { return }
            do {
                try session.send(data, toPeers: [peerID], with: .reliable)
            } catch {
                log.error("Failed to respond to ping: \(error.localizedDescription, privacy: .public)")
            }
        case .pong:
            break
        }
    }
}
