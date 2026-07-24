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

    /// Latest normalized microphone level (0…1), updated per audio buffer and
    /// read from the main thread by the recording overlay's waveform. Guarded
    /// by its own lock so the audio thread and UI never contend on `lock`.
    private var _level: Float = 0
    private let levelLock = NSLock()

    var level: Float {
        levelLock.lock()
        defer { levelLock.unlock() }
        return _level
    }

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

        levelLock.lock()
        _level = 0
        levelLock.unlock()

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

        levelLock.lock()
        _level = 0
        levelLock.unlock()

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

        // Live level for the overlay: RMS of this buffer, gained into a 0…1
        // range for speech and low-pass smoothed so the waveform doesn't jump.
        var sumSquares: Float = 0
        for i in 0..<frames {
            let s = channel[0][i]
            sumSquares += s * s
        }
        let rms = (sumSquares / Float(frames)).squareRoot()
        // Perceptual curve: sqrt lifts quiet/normal speech (small RMS) into a
        // visible range while compressing loud peaks so they don't saturate.
        let normalized = min(1, rms.squareRoot() * 3)
        levelLock.lock()
        _level = _level * 0.6 + normalized * 0.4
        levelLock.unlock()
    }
}
