import Foundation
import AVFoundation
import VideoToolbox
import CoreGraphics

public protocol FrameCompressorType {
    func encode(pixelBuffer: CVPixelBuffer) async throws -> DisplayFrame
}

public final class FrameCompressor: FrameCompressorType {
    private let contextQueue = DispatchQueue(label: "jp.kawashimataiki.linkpad.encoder")
    private var compressionSession: VTCompressionSession?
    private let targetSize: CGSize

    public init(targetSize: CGSize) {
        self.targetSize = targetSize
        setupSession()
    }

    private func setupSession() {
        VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                   width: Int32(targetSize.width),
                                   height: Int32(targetSize.height),
                                   codecType: kCMVideoCodecType_HEVC,
                                   encoderSpecification: nil,
                                   imageBufferAttributes: nil,
                                   compressedDataAllocator: nil,
                                   outputCallback: nil,
                                   refcon: nil,
                                   compressionSessionOut: &compressionSession)
        if let session = compressionSession {
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        }
    }

    public func encode(pixelBuffer: CVPixelBuffer) async throws -> DisplayFrame {
        try await withCheckedThrowingContinuation { continuation in
            let opaqueValue = UInt(bitPattern: Unmanaged.passRetained(pixelBuffer).toOpaque())
            contextQueue.async {
                guard let pointer = UnsafeMutableRawPointer(bitPattern: opaqueValue) else {
                    continuation.resume(throwing: CompressionError.dataExtractionFailed)
                    return
                }
                let pixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(pointer).takeRetainedValue()
                guard let session = self.compressionSession else {
                    continuation.resume(throwing: CompressionError.sessionMissing)
                    return
                }

                var flags: VTEncodeInfoFlags = []
                let presentationTimeStamp = CMTime(value: CMTimeValue(CACurrentMediaTime() * 1000), timescale: 1000)
                let status = VTCompressionSessionEncodeFrame(session,
                                                              imageBuffer: pixelBuffer,
                                                              presentationTimeStamp: presentationTimeStamp,
                                                              duration: .invalid,
                                                              frameProperties: nil,
                                                              infoFlagsOut: &flags,
                                                              outputHandler: { status, _, buffer in
                    if status == noErr, let buffer, let dataBuffer = CMSampleBufferGetDataBuffer(buffer) {
                        var length = 0
                        var dataPointer: UnsafeMutablePointer<Int8>?
                        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                        if let pointer = dataPointer {
                            let data = Data(bytes: pointer, count: length)
                            let frame = DisplayFrame(size: self.targetSize, payload: data, isDelta: !flags.contains(.frameDropped))
                            continuation.resume(returning: frame)
                        } else {
                            continuation.resume(throwing: CompressionError.dataExtractionFailed)
                        }
                    } else {
                        continuation.resume(throwing: CompressionError.encodeFailed(status))
                    }
                })

                if status != noErr {
                    continuation.resume(throwing: CompressionError.encodeFailed(status))
                }
            }
        }
    }

    public enum CompressionError: Error {
        case sessionMissing
        case dataExtractionFailed
        case encodeFailed(OSStatus)
    }
}

extension FrameCompressor: @unchecked Sendable {}
