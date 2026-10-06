// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// An eight-byte boot-compatible keyboard report. Report ID belongs to the GATT descriptor, not these bytes.
public struct KeyboardStroke: Equatable, Sendable {
    public let usage: UInt8
    public let modifiers: UInt8
    public init(usage: UInt8 = 0, modifiers: UInt8 = 0) { self.usage = usage; self.modifiers = modifiers }
    public var data: Data { Data([modifiers,0,usage,0,0,0,0,0]) }
    public static let zero = KeyboardStroke()
    public static let enter = KeyboardStroke(usage:0x28)
    public static let shiftEnter = KeyboardStroke(usage:0x28,modifiers:2)
    public static let backspace = KeyboardStroke(usage:0x2a)
    public static let tab = KeyboardStroke(usage:0x2b)
    public static let space = KeyboardStroke(usage:0x2c)
    public static let escape = KeyboardStroke(usage:0x29)
    public static let right = KeyboardStroke(usage:0x4f)
    public static let left = KeyboardStroke(usage:0x50)
    public static let down = KeyboardStroke(usage:0x51)
    public static let up = KeyboardStroke(usage:0x52)
    public static let inputSource = KeyboardStroke(usage:0x2c,modifiers:1)
}
public enum KeyboardTextMode: String, CaseIterable, Sendable {
    case ascii, kanaReading
    public var title: String { self == .ascii ? "英数・ローマ字" : "かなの読み" }
}
public enum KeyboardError: Error, Equatable, LocalizedError {
    case empty, tooLong, unsupported, controlCharacter, busy, invalidTime
    public var errorDescription: String? {
        switch self {
        case .empty: return "文字を入力してください。Enterだけ送る場合はEnterボタンを使います。"
        case .tooLong: return "一度に送信できるのは256文字までです。"
        case .unsupported: return "この文字は直接送れません。日本語は「かなの読み」かローマ字で送り、iPhone側で変換してください。確定済みの漢字・絵文字の貼り付けは未対応です。"
        case .controlCharacter: return "改行・タブなどの制御文字は文章に含められません。EnterやTabボタンで明示的に送ってください。"
        case .busy: return "文字を転送中です。完了するか、転送を中止してから操作してください。"
        case .invalidTime: return "転送タイミングを確認できなかったため停止しました。"
        }
    }
}

public struct KeyboardPlan: Sendable {
    public let strokes: [KeyboardStroke]
    public let wireText: String
    private init(strokes: [KeyboardStroke], wireText: String) { self.strokes=strokes;self.wireText=wireText }
    public var reports: [KeyboardStroke] { [.zero] + strokes.flatMap { [$0,.zero] } }
    public static func key(_ stroke: KeyboardStroke) -> Self { Self(strokes:[stroke],wireText:"") }
    /// Validate the entire draft before producing any reports. Never silently delete unsupported Unicode.
    public static func text(_ text: String, mode: KeyboardTextMode, enter: Bool) throws -> Self {
        guard !text.isEmpty else { throw KeyboardError.empty }
        guard text.utf8.count <= 4096, text.count <= 256 else { throw KeyboardError.tooLong }
        let normalized = mode == .kanaReading ? text.precomposedStringWithCanonicalMapping : text
        var wire=""
        for scalar in normalized.unicodeScalars {
            if scalar.value < 32 || scalar.value == 127 { throw KeyboardError.controlCharacter }
            if (32...126).contains(scalar.value) { wire.unicodeScalars.append(scalar); continue }
            guard mode == .kanaReading else { throw KeyboardError.unsupported }
            let hiragana = (0x30a1...0x30f6).contains(scalar.value) ? UnicodeScalar(scalar.value-0x60)! : scalar
            if let mapped = kana[String(hiragana)] { wire += mapped }
            else if let mapped = punctuation[String(scalar)] { wire += mapped }
            else { throw KeyboardError.unsupported }
        }
        guard wire.utf8.count <= 1024 else { throw KeyboardError.tooLong }
        var strokes = try wire.utf8.map { try ascii($0) }
        if enter { strokes.append(.enter) }
        return Self(strokes:strokes,wireText:wire)
    }
    private static func ascii(_ byte: UInt8) throws -> KeyboardStroke {
        if (97...122).contains(byte) { return KeyboardStroke(usage:byte-97+4) }
        if (65...90).contains(byte) { return KeyboardStroke(usage:byte-65+4,modifiers:2) }
        if (49...57).contains(byte) { return KeyboardStroke(usage:byte-49+30) }
        if byte == 48 { return KeyboardStroke(usage:39) }
        if byte == 32 { return .space }
        let lower = Array("-=[]\\;'`,./".utf8), upper = Array("_+{}|:\"~<>?".utf8)
        let usages: [UInt8] = [45,46,47,48,49,51,52,53,54,55,56]
        if let index=lower.firstIndex(of:byte) { return KeyboardStroke(usage:usages[index]) }
        if let index=upper.firstIndex(of:byte) { return KeyboardStroke(usage:usages[index],modifiers:2) }
        if let index=Array("!@#$%^&*()".utf8).firstIndex(of:byte) { return KeyboardStroke(usage:UInt8(30+index),modifiers:2) }
        throw KeyboardError.unsupported
    }
    // Deliberately a reading converter, not a kanji/emoji or arbitrary Unicode transport.
    private static let kana: [String:String] = {
        let rows=[("あいうえお","a i u e o"),("かきくけこ","ka ki ku ke ko"),("さしすせそ","sa shi su se so"),
                  ("たちつてと","ta chi tsu te to"),("なにぬねの","na ni nu ne no"),("はひふへほ","ha hi fu he ho"),
                  ("まみむめも","ma mi mu me mo"),("やゆよ","ya yu yo"),("らりるれろ","ra ri ru re ro"),
                  ("わをん","wa wo n'"),("がぎぐげご","ga gi gu ge go"),("ざじずぜぞ","za ji zu ze zo"),
                  ("だぢづでど","da di du de do"),("ばびぶべぼ","ba bi bu be bo"),("ぱぴぷぺぽ","pa pi pu pe po"),
                  ("ぁぃぅぇぉ","xa xi xu xe xo"),("ゃゅょっゎゔ","xya xyu xyo xtu xwa vu")]
        var map: [String:String]=[:]
        for (letters,keys) in rows { for (letter,key) in zip(letters,keys.split(separator:" ")) { map[String(letter)]=String(key) } }
        return map
    }()
    private static let punctuation = ["ー":"-","、":",","。":".","「":"[","」":"]","　":" "]
}

/// A finite transaction, independent of UI and radio callbacks. Only accepted reports advance it.
public struct KeyboardTransaction: Sendable {
    public private(set) var peer: UUID?
    private var reports: [KeyboardStroke]=[]
    private var index=0
    private var nextTime: TimeInterval=0
    private var lastProgress: TimeInterval=0
    public init() {}
    public var isActive: Bool { peer != nil && index < reports.count }
    public var remaining: Int { max(0,reports.count-index) }
    public mutating func begin(_ plan: KeyboardPlan, peer: UUID, at time: TimeInterval) throws {
        guard !isActive else { throw KeyboardError.busy }
        guard time.isFinite, time >= 0, time + 0.02 > time else { throw KeyboardError.invalidTime }
        self.peer=peer;reports=plan.reports;index=0;nextTime=time;lastProgress=time
    }
    public func due(at time: TimeInterval) -> KeyboardStroke? {
        guard isActive,time.isFinite,time >= nextTime,!isStalled(at:time) else { return nil }
        return reports[index]
    }
    public func isStalled(at time: TimeInterval) -> Bool {
        isActive && (!time.isFinite || time < lastProgress || time-lastProgress > 0.5)
    }
    public mutating func accept(at time: TimeInterval) {
        guard due(at:time) != nil else { return }
        index += 1;lastProgress=time;nextTime=time+0.02
        if !isActive { reports.removeAll(keepingCapacity:false);index=0;peer=nil }
    }
    /// Caller must send a neutral keyboard report to the returned peer; never replay remaining reports.
    @discardableResult public mutating func cancel() -> UUID? {
        let target=peer;peer=nil;reports.removeAll(keepingCapacity:false);index=0;return target
    }
}
public enum KeyboardPolicy {
    public static func canSend(peer: UUID?, receivers: Set<UUID>, foreground: Bool, mouseRelaying: Bool) -> Bool {
        foreground && !mouseRelaying && peer.map { receivers.contains($0) } == true
    }
}
