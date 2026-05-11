import Foundation

public enum TranscriptionError: Error, LocalizedError {
    case emptyRecording
    case modelUnavailable
    case whisperRuntimeUnavailable
    case whisperCommandFailed(String)
    case transcriptFileMissing(String)
    case transcriptEmpty

    public var errorDescription: String? {
        switch self {
        case .emptyRecording: "No speech was captured."
        case .modelUnavailable: "The selected model is not ready."
        case .whisperRuntimeUnavailable: "Local Whisper runtime is not available."
        case let .whisperCommandFailed(reason): "Whisper failed: \(reason)"
        case let .transcriptFileMissing(reason): "Whisper output missing: \(reason)"
        case .transcriptEmpty: "Whisper returned empty text. Check microphone input."
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

        throw TranscriptionError.transcriptEmpty
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
        let stdoutURL = workDirectory.appendingPathComponent("stdout.log")
        let stderrURL = workDirectory.appendingPathComponent("stderr.log")
        try writeWAV(recording, to: audioURL)
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

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

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()
        try? stdoutHandle.close()
        try? stderrHandle.close()

        guard process.terminationStatus == 0 else {
            throw TranscriptionError.whisperCommandFailed(diagnosticMessage(stdoutURL: stdoutURL, stderrURL: stderrURL))
        }

        guard let transcriptURL = transcriptFile(in: workDirectory, preferredName: "dictation.txt") else {
            throw TranscriptionError.transcriptFileMissing(diagnosticMessage(stdoutURL: stdoutURL, stderrURL: stderrURL))
        }
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw TranscriptionError.transcriptEmpty
        }
        return transcript
    }

    private static func findWhisperExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func transcriptFile(in directory: URL, preferredName: String) -> URL? {
        let preferred = directory.appendingPathComponent(preferredName)
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return files
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private static func diagnosticMessage(stdoutURL: URL, stderrURL: URL) -> String {
        let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let message = [stderr, stdout]
            .joined(separator: "\n")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.contains("%|") }

        return String((message ?? "No diagnostic output.").prefix(140))
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
