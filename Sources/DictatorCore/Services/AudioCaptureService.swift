import AVFoundation
import Combine
import Foundation

@MainActor
public final class AudioCaptureService: ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var level: Double = 0

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 44_100

    public init() {}

    public func start() throws {
        guard !isRecording else { return }

        samples.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            let chunk = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            let rms = sqrt(chunk.reduce(0) { $0 + Double($1 * $1) } / max(Double(chunk.count), 1))

            self.lock.lock()
            self.samples.append(contentsOf: chunk)
            self.lock.unlock()

            Task { @MainActor in
                self.level = min(max(rms * 12, 0), 1)
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    public func stop() -> AudioRecording {
        guard isRecording else {
            return AudioRecording(samples: [], sampleRate: sampleRate)
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()

        return AudioRecording(samples: captured, sampleRate: sampleRate)
    }

    public func cancel() {
        if isRecording {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        lock.lock()
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
        isRecording = false
        level = 0
    }
}
