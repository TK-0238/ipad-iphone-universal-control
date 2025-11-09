import Foundation
import AVFoundation
import CoreGraphics
import CoreImage
import UniformTypeIdentifiers
import ImageIO

public protocol FrameCompressorType {
    func encode(pixelBuffer: CVPixelBuffer) async throws -> DisplayFrame
}

public final class FrameCompressor: FrameCompressorType {
    private let contextQueue = DispatchQueue(label: "jp.kawashimataiki.linkpad.encoder")
    private let targetSize: CGSize
    private let ciContext: CIContext

    public init(targetSize: CGSize) {
        self.targetSize = targetSize
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    public func encode(pixelBuffer: CVPixelBuffer) async throws -> DisplayFrame {
        try await withCheckedThrowingContinuation { continuation in
            let retainedBuffer = RetainedPixelBuffer(buffer: pixelBuffer)
            contextQueue.async {
                let buffer = retainedBuffer.take()
                do {
                    let data = try self.encodeImageData(from: buffer)
                    let frame = DisplayFrame(size: self.targetSize, payload: data, isDelta: false)
                    continuation.resume(returning: frame)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func encodeImageData(from pixelBuffer: CVPixelBuffer) throws -> Data {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = scalingFactors(for: ciImage.extent.size)
        let scaled = ciImage
            .transformed(by: CGAffineTransform(scaleX: scale.width, y: scale.height))
            .transformed(by: CGAffineTransform(translationX: -ciImage.extent.origin.x * scale.width,
                                               y: -ciImage.extent.origin.y * scale.height))

        guard let cgImage = ciContext.createCGImage(scaled, from: CGRect(origin: .zero, size: targetSize)) else {
            throw CompressionError.imageCreationFailed
        }

        return try writeJPEG(from: cgImage)
    }

    private func scalingFactors(for sourceSize: CGSize) -> CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        return CGSize(width: targetSize.width / sourceSize.width,
                      height: targetSize.height / sourceSize.height)
    }

    private func writeJPEG(from image: CGImage) throws -> Data {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CompressionError.destinationCreationFailed
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.65]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CompressionError.encodeFailed
        }
        return mutableData as Data
    }

    public enum CompressionError: Error {
        case imageCreationFailed
        case destinationCreationFailed
        case encodeFailed
    }
}

private struct RetainedPixelBuffer: @unchecked Sendable {
    private let opaquePointer: UnsafeMutableRawPointer

    init(buffer: CVPixelBuffer) {
        self.opaquePointer = Unmanaged.passRetained(buffer).toOpaque()
    }

    func take() -> CVPixelBuffer {
        Unmanaged<CVPixelBuffer>.fromOpaque(opaquePointer).takeRetainedValue()
    }
}

extension FrameCompressor: @unchecked Sendable {}
