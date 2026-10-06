import Foundation
import XCTest
@testable import MouseLinkCore

final class HIDRegistryExhaustiveTests: XCTestCase {
    func testEveryTwoHostEndpointModeAndSuspendCombination() {
        let a=UUID(), b=UUID()
        let endpoints:[HIDInputEndpoint]=[.mouseReport,.mouseBoot,.keyboardReport,.keyboardBoot]
        // 16 endpoint sets x 2 protocol modes x 2 suspend states = 64 states per peer.
        // Check all 4096 two-peer combinations against an independent bit-mask oracle.
        for sa in 0..<64 { for sb in 0..<64 {
            var registry=HIDPeerRegistry();var expectedMouse=Set<UUID>(),expectedKeyboard=Set<UUID>()
            for (peer,state) in [(a,sa),(b,sb)] {
                for bit in 0..<4 where state & (1<<bit) != 0 { registry.subscribe(endpoints[bit],peer:peer) }
                let boot=state & 16 != 0, suspended=state & 32 != 0
                registry.setProtocol(boot ? 0 : 1,peer:peer);registry.setSuspended(suspended,peer:peer)
                if !suspended && state & (boot ? 2 : 1) != 0 { expectedMouse.insert(peer) }
                if !suspended && state & (boot ? 8 : 4) != 0 { expectedKeyboard.insert(peer) }
            }
            XCTAssertEqual(registry.mouseReceivers,expectedMouse,"states \(sa),\(sb)")
            XCTAssertEqual(registry.keyboardReceivers,expectedKeyboard,"states \(sa),\(sb)")
        } }
    }
    func testEveryInvalidProtocolByteLeavesBothHostsUnchanged() {
        var registry=HIDPeerRegistry();let a=UUID(),b=UUID()
        registry.subscribe(.mouseReport,peer:a);registry.subscribe(.keyboardBoot,peer:b);registry.setProtocol(0,peer:b)
        let generation=registry.epoch
        for value in 2...255 {
            XCTAssertFalse(registry.setProtocol(UInt8(value),peer:a))
            XCTAssertEqual(registry.epoch,generation)
            XCTAssertEqual(registry.mouseReceivers,[a]);XCTAssertEqual(registry.keyboardReceivers,[b])
        }
    }
}
