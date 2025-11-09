import Foundation
import CoreGraphics
import QuartzCore
#if canImport(UIKit)
import UIKit
public typealias PlatformModifierFlags = UIKeyModifierFlags
#else
import AppKit
public typealias PlatformModifierFlags = NSEvent.ModifierFlags
#endif

public enum ControlRole: String, Codable, CaseIterable, Sendable {
    case controller
    case display
    case mirror
}

public struct KeyEvent: Codable, Sendable, Hashable {
    public let key: String
    public let modifiersValue: PlatformModifierFlags.RawValue
    public let isKeyDown: Bool
    public let timestamp: TimeInterval

    public var modifiers: PlatformModifierFlags {
        PlatformModifierFlags(rawValue: modifiersValue)
    }

    public init(key: String, modifiers: PlatformModifierFlags = [], isKeyDown: Bool, timestamp: TimeInterval = CACurrentMediaTime()) {
        self.key = key
        self.modifiersValue = modifiers.rawValue
        self.isKeyDown = isKeyDown
        self.timestamp = timestamp
    }
}

public struct PointerEvent: Codable, Sendable, Hashable {
    public struct ButtonState: OptionSet, Codable, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let primary = ButtonState(rawValue: 1 << 0)
        public static let secondary = ButtonState(rawValue: 1 << 1)
        public static let auxiliary = ButtonState(rawValue: 1 << 2)
    }

    public let location: CGPoint
    public let delta: CGVector
    public let buttons: ButtonState
    public let timestamp: TimeInterval

    public init(location: CGPoint, delta: CGVector, buttons: ButtonState, timestamp: TimeInterval = CACurrentMediaTime()) {
        self.location = location
        self.delta = delta
        self.buttons = buttons
        self.timestamp = timestamp
    }
}

public enum InputEventPayload: Codable, Sendable, Hashable {
    case key(KeyEvent)
    case pointer(PointerEvent)
}

public struct DisplayFrame: Codable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: TimeInterval
    public let size: CGSize
    public let payload: Data
    public let isDelta: Bool

    public init(id: UUID = UUID(), timestamp: TimeInterval = CACurrentMediaTime(), size: CGSize, payload: Data, isDelta: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.size = size
        self.payload = payload
        self.isDelta = isDelta
    }
}
