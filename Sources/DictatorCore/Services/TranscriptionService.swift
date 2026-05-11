import Foundation

public enum TranscriptionError: Error, LocalizedError {
    case emptyRecording
    case modelUnavailable
    case whisperRuntimeUnavailable
    case whisperFailed

    public var errorDescription: String? {
        switch self {
        case .emptyRecording: "No speech was captured."
        case .modelUnavailable: "The selected model is not ready."
        case .whisperRuntimeUnavailable: "Local Whisper runtime is not available."
        case .whisperFailed: "Local Whisper did not return a transcript."
        }
    }
}

public final class TranscriptionService {
    public init() {}

    public func transcribe(
        _ recording: AudioRecording,
        language: DictationLanguage,
        model: ModelOption,
        modelState: ModelDownloadState
    ) async throws -> String {
        guard modelState == .ready else { throw TranscriptionError.modelUnavailable }
        guard recording.duration > 0.15 else { throw TranscriptionError.emptyRecording }

        if let transcript = try await Self.transcribeWithLocalWhisper(recording, language: language, model: model) {
            return transcript
        }

        throw TranscriptionError.whisperFailed
    }

    private static func transcribeWithLocalWhisper(
        _ recording: AudioRecording,
        language: DictationLanguage,
        model: ModelOption
    ) async throws -> String? {
        try await Task.detached(priority: .userInitiated) {
            try transcribeWithLocalWhisperSync(recording, language: language, model: model)
        }.value
    }

    private static func transcribeWithLocalWhisperSync(
        _ recording: AudioRecording,
        language: DictationLanguage,
        model: ModelOption
    ) throws -> String? {
        guard let whisperPath = findWhisperExecutable() else {
            throw TranscriptionError.whisperRuntimeUnavailable
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dictator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workDirectory)
        }

        let audioURL = workDirectory.appendingPathComponent("dictation.wav")
        try writeWAV(recording, to: audioURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [
            audioURL.path,
            "--model", model.rawValue,
            "--language", language.rawValue,
            "--output_format", "txt",
            "--output_dir", workDirectory.path,
            "--fp16", "False"
        ]

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TranscriptionError.whisperFailed
        }

        let transcriptURL = workDirectory.appendingPathComponent("dictation.txt")
        guard FileManager.default.fileExists(atPath: transcriptURL.path) else { return nil }
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript.isEmpty ? nil : transcript
    }

    private static func findWhisperExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func writeWAV(_ recording: AudioRecording, to url: URL) throws {
        var data = Data()
        let sampleRate = UInt32(recording.sampleRate)
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let pcmDataSize = UInt32(recording.samples.count * 2)

        data.append("RIFF".data(using: .ascii)!)
        data.appendLittleEndian(UInt32(36) + pcmDataSize)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channels)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append("data".data(using: .ascii)!)
        data.appendLittleEndian(pcmDataSize)

        for sample in recording.samples {
            let clipped = max(-1, min(1, sample))
            data.appendLittleEndian(Int16(clipped * Float(Int16.max)))
        }

        try data.write(to: url, options: [.atomic])
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(contentsOf: buffer)
        }
    }
}
