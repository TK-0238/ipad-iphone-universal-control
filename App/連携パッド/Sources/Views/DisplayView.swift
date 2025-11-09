import SwiftUI
import SharedControlKit

struct DisplayView: View {
    @EnvironmentObject private var viewModel: AppSessionViewModel
    @State private var isSharing = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(isSharing ? "配信中" : "待機中")
                    .font(.title3)
                Spacer()
                Toggle("画面共有", isOn: Binding(
                    get: { isSharing },
                    set: { newValue in
                        isSharing = newValue
                        if newValue {
                            viewModel.startScreenShare(targetSize: CGSize(width: 1280, height: 720))
                        } else {
                            viewModel.stopScreenShare()
                        }
                    })
                )
                .toggleStyle(.switch)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer()
        }
    }
}
