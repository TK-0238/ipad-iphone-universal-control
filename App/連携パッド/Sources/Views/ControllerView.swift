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
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Color.black
                    Text("映像待機中")
                        .foregroundStyle(.white)
                }

                if let pointer {
                    let position = scaled(pointer: pointer, in: proxy.size, frameSize: frame?.size)
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

    private func scaled(pointer: PointerEvent, in containerSize: CGSize, frameSize: CGSize?) -> CGPoint {
        let clampedX = min(max(pointer.location.x, 0), 1)
        let clampedY = min(max(pointer.location.y, 0), 1)

        guard let frameSize else {
            return CGPoint(x: clampedX * containerSize.width,
                           y: clampedY * containerSize.height)
        }

        let safeFrameWidth = max(frameSize.width, 1)
        let safeFrameHeight = max(frameSize.height, 1)
        let scale = min(containerSize.width / safeFrameWidth,
                        containerSize.height / safeFrameHeight)
        let renderedSize = CGSize(width: safeFrameWidth * scale,
                                  height: safeFrameHeight * scale)
        let origin = CGPoint(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2
        )

        return CGPoint(
            x: origin.x + clampedX * renderedSize.width,
            y: origin.y + clampedY * renderedSize.height
        )
    }
}
