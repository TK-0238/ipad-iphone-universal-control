// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

/// Schematic device arrangement. Never represents captured screens or a remote pointer position.
struct DeviceArrangementView: View {
    let placement: DevicePlacement
    let remoteActive: Bool
    let connected: Bool
    let canStart: Bool
    let switchToPhone: () -> Void
    let switchToPad: () -> Void
    let move: (DevicePlacement) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let tabletWidth = min(310,max(140,geometry.size.width*0.48))
            let phoneWidth = min(92,max(62,geometry.size.width*0.15))
            HStack(alignment:.center,spacing:28) {
                if placement == .left { phone(width:phoneWidth) }
                tablet(width:tabletWidth)
                if placement == .right { phone(width:phoneWidth) }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(height:260)
            // Only schematic labels are capped. Outside controls retain the user's full text size.
            .dynamicTypeSize(...DynamicTypeSize.large)
            // A container identifier is inherited by SwiftUI descendants and can mask
            // the phone/drag-handle identifiers. Keep identifiers on the controls only.
    }
    private func tablet(width:CGFloat) -> some View {
        VStack(spacing:12) {
            if remoteActive {
                Button(action:switchToPad) { tabletPlate(width:width) }
                    .buttonStyle(.plain).accessibilityLabel("このiPadに戻る")
            } else {
                // A disabled Button dims its complete label, incorrectly suggesting this iPad is offline.
                tabletPlate(width:width).accessibilityElement(children:.ignore)
                    .accessibilityLabel("このiPad、操作中")
            }
            Text(remoteActive ? "待機中" : "操作中").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func tabletPlate(width:CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius:17).fill(Color.primary.opacity(0.85))
            RoundedRectangle(cornerRadius:10).fill(Color(uiColor:.systemBackground)).padding(8)
            VStack(spacing:10) {
                Image(systemName:"cursorarrow").font(.system(size:25,weight:.medium))
                Text("このiPad").font(.subheadline.weight(.medium)).lineLimit(1)
            }.foregroundStyle(remoteActive ? Color.secondary : Color.accentColor)
            if !remoteActive { RoundedRectangle(cornerRadius:18).stroke(Color.accentColor,lineWidth:2).padding(-3) }
        }.frame(width:width,height:width*0.64)
    }
    private func phone(width:CGFloat) -> some View {
        VStack(spacing:10) {
            if canStart {
                Button(action:switchToPhone) { phonePlate(width:width) }
                    .buttonStyle(.plain).accessibilityLabel("選択中のiPhoneに切り替え")
                    .accessibilityIdentifier("phone-display")
            } else {
                phonePlate(width:width).accessibilityElement(children:.ignore)
                    .accessibilityLabel(remoteActive ? "iPhone、転送中" : (connected ? "受信先、接続済み" : "iPhone、未接続"))
                    .accessibilityIdentifier("phone-display")
            }
            Text(remoteActive ? "転送中" : (connected ? "接続済み" : "未接続"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            // Separate drag surface avoids turning a placement drag into an input-start click.
            Text("↔").font(.footnote.weight(.semibold)).frame(width:60,height:44)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:24).onEnded { value in
                    guard !remoteActive, abs(value.translation.width) >= 60 else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration:0.2)) { move(value.translation.width < 0 ? .left : .right) }
                })
                .accessibilityLabel("iPhoneの配置をドラッグ。左右のボタンでも変更できます")
                .accessibilityIdentifier("placement-drag-handle")
                .accessibilityAdjustableAction { direction in
                    guard !remoteActive else { return }
                    move(direction == .increment ? .right : .left)
                }
        }
    }
    private func phonePlate(width:CGFloat) -> some View {
        ZStack(alignment:.top) {
            RoundedRectangle(cornerRadius:17).fill(Color.primary.opacity(connected ? 0.85 : 0.3))
            RoundedRectangle(cornerRadius:12).fill(Color(uiColor:.systemBackground)).padding(5)
            Capsule().fill(Color.primary.opacity(0.8)).frame(width:27,height:6).padding(.top,10)
            VStack(spacing:10) {
                Image(systemName:remoteActive ? "cursorarrow.rays" : "iphone").font(.system(size:23,weight:.medium))
                Text("iPhone").font(.caption.weight(.semibold)).lineLimit(1)
            }.foregroundStyle(remoteActive ? Color.accentColor : Color.secondary).frame(maxHeight:.infinity)
            if remoteActive { RoundedRectangle(cornerRadius:18).stroke(Color.accentColor,lineWidth:2).padding(-3) }
        }.frame(width:width,height:width*1.85)
    }
}
