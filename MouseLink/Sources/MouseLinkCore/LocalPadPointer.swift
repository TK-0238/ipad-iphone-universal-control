// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Relative input from an explicitly visible pad, never an estimate of the OS or remote cursor.
public struct LocalPadPointer: Sendable {
    private var last: (x: Double, y: Double)?
    private var size: (width: Double, height: Double)?
    private var held: UInt8 = 0
    private var motion = MotionAccumulator()
    public init() {}
    public var isInside: Bool { last != nil }

    public mutating func move(x: Double, y: Double, width: Double, height: Double,
                              gain: Double = 1, externalButtonsDown: Bool = false) throws -> [MouseFrame] {
        guard [x,y,width,height,gain].allSatisfy(\.isFinite), width > 0, height > 0,
              width <= 8192, height <= 8192, (0.25...3).contains(gain) else {
            throw RelayFailure.invalidMotion
        }
        if let size, size.width != width || size.height != height { return leave() }
        guard x >= 0, y >= 0, x < width, y < height else { return leave() }
        guard let previous = last else {
            guard !externalButtonsDown else { return [] }
            last = (x,y); size = (width,height); return []
        }
        let result = try motion.add(x:(x-previous.x)*gain,y:(y-previous.y)*gain,wheel:0,buttons:held)
        last = (x,y); return result
    }
    public mutating func buttons(_ value: UInt8) -> [MouseFrame] {
        guard isInside else { return [] }
        let next = value & 3
        guard next != held else { return [] }
        held = next; return [MouseFrame(buttons:held)]
    }
    public mutating func scroll(_ value: Double) throws -> [MouseFrame] {
        guard isInside else { return [] }
        return try motion.add(x:0,y:0,wheel:value,buttons:held)
    }
    @discardableResult public mutating func leave() -> [MouseFrame] {
        let releases: [MouseFrame] = held == 0 ? [] : [.zero]
        last = nil; size = nil; held = 0; motion = MotionAccumulator()
        return releases
    }
}
