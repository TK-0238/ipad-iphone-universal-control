import Foundation
import ReplayKit
import Combine
import AVFoundation
import SharedControlKit

public final class ScreenCaptureCoordinator: NSObject, ObservableObject {
    public enum CaptureState {
        case idle
        case starting
        case running
        case failed(Error)
    }

    @Published public private(set) var state: CaptureState = .idle
    private let compressor: FrameCompressorType
    private let recorder = RPScreenRecorder.shared()
    private let frameSubject = PassthroughSubject<DisplayFrame, Never>()
    public var frames: AnyPublisher<DisplayFrame, Never> { frameSubject.eraseToAnyPublisher() }

    public init(targetSize: CGSize) {
        self.compressor = FrameCompressor(targetSize: targetSize)
        super.init()
    }

    public func start() {
        if case .running = state { return }
        state = .starting
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        recorder.startCapture(handler: { [weak self] sampleBuffer, _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.state = .failed(error) }
                return
            }
            guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                Task {
                    if let frame = try? await self.compressor.encode(pixelBuffer: pixelBuffer) {
                        self.frameSubject.send(frame)
                    }
                }
            }
        }, completionHandler: { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.state = .failed(error)
                } else {
                    self?.state = .running
                }
            }
        })
    }

    public func stop() {
        recorder.stopCapture { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.state = .failed(error)
                } else {
                    self?.state = .idle
                }
            }
        }
    }
}
