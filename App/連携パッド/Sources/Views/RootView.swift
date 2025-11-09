import SwiftUI
import SharedControlKit
import MultipeerConnectivity

struct RootView: View {
    @EnvironmentObject private var viewModel: AppSessionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                rolePicker
                ConnectionStatusBanner(state: viewModel.connectionState, latency: viewModel.latency)
                switch viewModel.role {
                case .controller:
                    ControllerView()
                case .display, .mirror:
                    DisplayView()
                }
                Spacer()
            }
            .padding()
            .navigationTitle("連携パッド")
        }
    }

    private var rolePicker: some View {
        Picker("役割", selection: $viewModel.role) {
            ForEach(ControlRole.allCases, id: \.self) { role in
                Text(label(for: role)).tag(role)
            }
        }
        .pickerStyle(.segmented)
    }

    private func label(for role: ControlRole) -> String {
        switch role {
        case .controller: return "入力側"
        case .display: return "表示側"
        case .mirror: return "ミラー"
        }
    }
}
