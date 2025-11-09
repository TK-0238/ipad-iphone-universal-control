import SwiftUI
import SharedControlKit
import MultipeerConnectivity

struct ConnectionStatusBanner: View {
    let state: SessionState
    let latency: TimeInterval

    var body: some View {
        HStack {
            Image(systemName: icon)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
            }
            Spacer()
        }
        .padding()
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var icon: String {
        switch state {
        case .idle: return "wave.3.right"
        case .advertising: return "dot.radiowaves.right"
        case .browsing: return "magnifyingglass"
        case .connected: return "bolt.horizontal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var title: String {
        switch state {
        case .idle: return "未接続"
        case .advertising: return "待ち受け中"
        case .browsing: return "探索中"
        case .connected(let peer): return "接続: \(peer.displayName)"
        case .failed: return "失敗"
        }
    }

    private var subtitle: String {
        switch state {
        case .connected:
            return String(format: "往復 %.0f ms", latency * 1000)
        case .failed(let error):
            return error.localizedDescription
        default:
            return "遷移待ち…"
        }
    }

    private var background: some ShapeStyle {
        switch state {
        case .idle: return Color.gray.opacity(0.2)
        case .advertising, .browsing: return Color.blue.opacity(0.2)
        case .connected: return Color.green.opacity(0.3)
        case .failed: return Color.red.opacity(0.3)
        }
    }
}
