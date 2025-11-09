import SwiftUI
import SharedControlKit
import MultipeerConnectivity
import UIKit

struct ControllerView: View {
    @EnvironmentObject private var viewModel: AppSessionViewModel
    @State private var targetPeer: MCPeerID?

    var body: some View {
        VStack(spacing: 12) {
            peerList
            RemoteDisplaySurface(frame: viewModel.latestFrame, pointer: viewModel.remotePointer)
                .overlay(
                    InputCaptureView { event in
                        viewModel.emitLocal(event)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: 360)
                .background(.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    private var peerList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("検出された端末")
                .font(.headline)
            if viewModel.discoveredPeers.isEmpty {
                Text("待機中…")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(viewModel.discoveredPeers, id: \.self) { peer in
                            Button {
                                viewModel.invite(peer: peer)
                                targetPeer = peer
                            } label: {
                                Label(peer.displayName, systemImage: targetPeer == peer ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }
}

struct RemoteDisplaySurface: View {
    let frame: DisplayFrame?
    let pointer: PointerEvent?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let image = image(from: frame) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Color.black
                    Text("映像待機中")
                        .foregroundStyle(.white)
                }

                if let pointer {
                    let position = scaled(pointer: pointer, in: proxy.size, frame: frame)
                    Circle()
                        .fill(.cyan.opacity(0.8))
                        .frame(width: 18, height: 18)
                        .position(x: position.x, y: position.y)
                        .animation(.easeOut(duration: 0.05), value: position)
                }
            }
        }
    }

    private func image(from frame: DisplayFrame?) -> UIImage? {
        guard let frame else { return nil }
        return UIImage(data: frame.payload)
    }

    private func scaled(pointer: PointerEvent, in size: CGSize, frame: DisplayFrame?) -> CGPoint {
        guard let frame else { return pointer.location }
        let scaleX = size.width / frame.size.width
        let scaleY = size.height / frame.size.height
        return CGPoint(x: pointer.location.x * scaleX, y: pointer.location.y * scaleY)
    }
}
