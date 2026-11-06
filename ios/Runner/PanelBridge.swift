import CoreML
import Flutter
import Foundation

/// On-device panel detection for lib/services/panel_detector.dart: a 640x640
/// RGBA letterbox in, PanelDetector's raw rows (cx, cy, w, h, objectness, panel
/// score) out as Float32. Cutoff, NMS and reading order stay in Dart.
final class PanelBridge {
    private static let size = 640
    private let channel: FlutterMethodChannel
    private let queue = DispatchQueue(label: "app.comic_reader.panels", qos: .userInitiated)
    // Loaded on first use (off the main thread); nil if the model is missing or fails to load.
    private lazy var model: MLModel? = {
        guard let url = Bundle.main.url(forResource: "PanelDetector", withExtension: "mlmodelc") else { return nil }
        return try? MLModel(contentsOf: url, configuration: MLModelConfiguration())
    }()

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "app.comic_reader/panels", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "detect", let rgba = (call.arguments as? FlutterStandardTypedData)?.data,
                  rgba.count == Self.size * Self.size * 4, let self else {
                result(FlutterMethodNotImplemented)
                return
            }
            self.queue.async {
                let out = self.detect(rgba)
                DispatchQueue.main.async { result(out) }
            }
        }
    }

    private func detect(_ rgba: Data) -> Any {
        guard let model else {
            return FlutterError(code: "NO_MODEL", message: "PanelDetector didn't load", details: nil)
        }
        guard let buffer = Self.bgraBuffer(rgba) else {
            return FlutterError(code: "BUFFER", message: "couldn't make the input buffer", details: nil)
        }
        do {
            let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)])
            guard let raw = try model.prediction(from: input).featureValue(for: "raw")?.multiArrayValue else {
                return FlutterError(code: "OUTPUT", message: "no raw output", details: nil)
            }
            // The model computes in Float16; this also copies out of any strided layout.
            let scalars = MLShapedArray<Float>(converting: raw).scalars
            return FlutterStandardTypedData(float32: scalars.withUnsafeBufferPointer { Data(buffer: $0) })
        } catch {
            return FlutterError(code: "PREDICT", message: error.localizedDescription, details: nil)
        }
    }

    /// RGBA bytes to the BGRA pixel buffer Core ML's image input takes.
    private static func bgraBuffer(_ rgba: Data) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, attrs, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        rgba.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            for y in 0..<size {
                let row = base + y * rowBytes
                for x in 0..<size {
                    let s = (y * size + x) * 4, d = x * 4
                    row[d] = src[s + 2]
                    row[d + 1] = src[s + 1]
                    row[d + 2] = src[s]
                    row[d + 3] = 255
                }
            }
        }
        return buffer
    }
}
