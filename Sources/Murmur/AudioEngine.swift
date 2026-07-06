import Foundation
import AVFoundation

/// Captures microphone audio and accumulates it as 16 kHz mono Float32 PCM —
/// the input format Whisper expects. Conversion from the device's native format
/// (typically 48 kHz stereo) happens per-buffer via AVAudioConverter.
final class AudioEngine {
    enum AudioError: LocalizedError {
        case noInputDevice
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .noInputDevice: return "No microphone input device available."
            case .converterUnavailable: return "Could not create audio format converter."
            }
        }
    }

    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioEngine.sampleRate,
        channels: 1,
        interleaved: false
    )!

    func start() throws {
        lock.lock()
        samples.removeAll()
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioError.noInputDevice
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterUnavailable
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// Stop capture and return everything recorded since start().
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil

        lock.lock()
        defer { lock.unlock() }
        let recorded = samples
        samples = []
        return recorded
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = converted.floatChannelData else { return }

        let frames = Int(converted.frameLength)
        guard frames > 0 else { return }

        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: frames))
        lock.unlock()
    }
}
