import Foundation

public enum TranscriptionError: Error, LocalizedError {
    case emptyRecording
    case modelUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyRecording: "No speech was captured."
        case .modelUnavailable: "The selected model is not ready."
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
        guard model == .gigaamV3E2ERNNT else { throw TranscriptionError.modelUnavailable }

        return try await GigaAMRuntime.transcribe(recording)
    }
}
