import XCTest
@testable import MouseLinkCore

final class EdgeHandoffTests: XCTestCase {
    private let context = EdgeHandoffContext(peer: "receiver-A", epoch: 7, side: .right)
    private func point(_ x: Double = 795, _ y: Double = 300, width: Double = 800, height: Double = 600) -> EdgePointer {
        EdgePointer(x: x, y: y, width: width, height: height)
    }
    private func primed(_ side: DevicePlacement = .right) -> EdgeHandoffGate {
        var g = EdgeHandoffGate()
        let c = EdgeHandoffContext(peer: "receiver-A", epoch: 7, side: side)
        g.arm(context: c)
        _ = g.observe(point(400), context: c, allowed: true, buttonsReleased: true, at: 0)
        return g
    }
    private func dwell(_ g: inout EdgeHandoffGate, context c: EdgeHandoffContext? = nil, x: Double = 795, start: Double = 0.1) -> Bool {
        var fired = false
        for i in 0...8 { fired = g.observe(point(x), context: c ?? context, allowed: true, buttonsReleased: true, at: start + Double(i)*0.1) || fired }
        return fired
    }
    func testUnarmedNeverFires() { var g = EdgeHandoffGate(); XCTAssertFalse(dwell(&g)); XCTAssertFalse(g.isArmed) }
    func testArmingWhileAlreadyAtEdgeRequiresInteriorFirst() {
        var g = EdgeHandoffGate(); g.arm(context: context); XCTAssertFalse(dwell(&g)); XCTAssertEqual(g.progress, 0)
    }
    func testIntentionalRightEdgeDwellFiresOnce() {
        var g = primed(); XCTAssertTrue(dwell(&g)); XCTAssertFalse(g.isArmed); XCTAssertFalse(dwell(&g, start: 1))
    }
    func testLeftPlacementUsesLeftEdge() {
        var g = primed(.left); let c = EdgeHandoffContext(peer: "receiver-A", epoch: 7, side: .left)
        XCTAssertTrue(dwell(&g, context: c, x: 5))
    }
    func testWrongEdgeCannotSwitch() { var g = primed(); XCTAssertFalse(dwell(&g, x: 5)) }
    func testPassThroughDoesNotFire() {
        var g = primed(); _ = g.observe(point(), context: context, allowed: true, buttonsReleased: true, at: 0.1)
        XCTAssertFalse(g.observe(point(400), context: context, allowed: true, buttonsReleased: true, at: 0.2)); XCTAssertEqual(g.progress, 0)
    }
    func testProgressAppearsBeforeSwitch() {
        var g = primed()
        for i in 1...4 { XCTAssertFalse(g.observe(point(), context: context, allowed: true, buttonsReleased: true, at: Double(i)*0.1)) }
        XCTAssertGreaterThan(g.progress, 0.3); XCTAssertLessThan(g.progress, 0.6)
    }
    func testPointerDepartureCancelsDwell() {
        var g = primed(); _ = g.observe(point(), context: context, allowed: true, buttonsReleased: true, at: 0.1)
        _ = g.observe(nil, context: context, allowed: true, buttonsReleased: true, at: 0.2)
        XCTAssertFalse(dwell(&g, start: 0.3))
    }
    func testDragCancelsAndNeedsAnotherInteriorVisit() {
        var g = primed(); _ = g.observe(point(), context: context, allowed: true, buttonsReleased: false, at: 0.1)
        XCTAssertFalse(dwell(&g, start: 0.2))
    }
    func testPermissionLossDisarms() {
        var g = primed(); _ = g.observe(point(), context: context, allowed: false, buttonsReleased: true, at: 0.1)
        XCTAssertFalse(g.isArmed); XCTAssertFalse(dwell(&g, start: 0.2))
    }
    func testReceiverChangeDisarms() {
        var g = primed(); let c = EdgeHandoffContext(peer: "receiver-B", epoch: 7, side: .right)
        XCTAssertFalse(dwell(&g, context: c)); XCTAssertFalse(g.isArmed)
    }
    func testSameReceiverReconnectDisarms() {
        var g = primed(); let c = EdgeHandoffContext(peer: "receiver-A", epoch: 8, side: .right)
        XCTAssertFalse(dwell(&g, context: c)); XCTAssertFalse(g.isArmed)
    }
    func testPlacementChangeDisarms() {
        var g = primed(); let c = EdgeHandoffContext(peer: "receiver-A", epoch: 7, side: .left)
        XCTAssertFalse(dwell(&g, context: c, x: 5)); XCTAssertFalse(g.isArmed)
    }
    func testMissingContextDisarms() {
        var g = primed(); _ = g.observe(point(), context: nil, allowed: true, buttonsReleased: true, at: 0.1); XCTAssertFalse(g.isArmed)
    }
    func testCornersDoNotTriggerSystemGestures() {
        for y in [0.0, 47, 553, 599] {
            var g = primed()
            for i in 1...15 { XCTAssertFalse(g.observe(point(795,y), context: context, allowed: true, buttonsReleased: true, at: Double(i)*0.1)) }
        }
    }
    func testOutOfBoundsAndNaNAreRejected() {
        for p in [point(-1),point(801),point(.nan),point(.infinity),point(795,-1),point(795,601),point(10,width:0),point(10,height:40)] {
            var g = primed(); XCTAssertFalse(g.observe(p, context: context, allowed: true, buttonsReleased: true, at: 0.1)); XCTAssertEqual(g.progress,0)
        }
    }
    func testInvalidAndNegativeTimeDisarm() {
        for t in [Double.nan, .infinity, -1] {
            var g = primed(); XCTAssertFalse(g.observe(point(), context: context, allowed: true, buttonsReleased: true, at: t)); XCTAssertFalse(g.isArmed)
        }
    }
    func testClockReversalDisarms() {
        var g = primed(); _ = g.observe(point(), context: context, allowed: true, buttonsReleased: true, at: 0.2)
        XCTAssertFalse(g.observe(point(), context: context, allowed: true, buttonsReleased: true, at: 0.1)); XCTAssertFalse(g.isArmed)
    }
    func testSuspendedTimerCannotFireOnResume() {
        var g = primed(); _ = g.observe(point(), context: context, allowed: true, buttonsReleased: true, at: 0.1)
        XCTAssertFalse(g.observe(point(), context: context, allowed: true, buttonsReleased: true, at: 5)); XCTAssertEqual(g.progress,0)
        XCTAssertFalse(dwell(&g,start:5.1))
    }
    func testResizeRequiresNewInteriorVisit() {
        var g = primed(); _ = g.observe(point(), context: context, allowed: true, buttonsReleased: true, at: 0.1)
        XCTAssertFalse(g.observe(point(995,width:1000),context:context,allowed:true,buttonsReleased:true,at:0.2))
        for i in 3...15 { XCTAssertFalse(g.observe(point(995,width:1000),context:context,allowed:true,buttonsReleased:true,at:Double(i)*0.1)) }
    }
    func testExplicitDisarmClearsProgress() { var g = primed(); g.disarm(); XCTAssertFalse(dwell(&g)); XCTAssertEqual(g.progress,0) }
    func testEmptyPeerCannotArm() { var g = EdgeHandoffGate(); g.arm(context: EdgeHandoffContext(peer:"",epoch:1,side:.right)); XCTAssertFalse(g.isArmed) }
    func testRearmingDoesNotReuseOldDwell() {
        var g = primed(); _ = g.observe(point(),context:context,allowed:true,buttonsReleased:true,at:0.1)
        g.arm(context:context); XCTAssertFalse(dwell(&g,start:0.2))
    }
    func testBoundaryOnlyStartsAfterInterior() {
        var g = primed(); XCTAssertTrue(dwell(&g,x:776))
        var h = primed(); XCTAssertFalse(dwell(&h,x:775))
    }
}
