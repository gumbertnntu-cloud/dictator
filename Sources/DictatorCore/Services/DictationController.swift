import Combine
import Foundation

@MainActor
public final class DictationController: ObservableObject {
    @Published public private(set) var state: DictationState = .idle

    private let settingsStore: SettingsStore
    private let modelDownloader: ModelDownloadService
    private let permissionService: PermissionService
    private let audioCapture: AudioCaptureService
    private let transcriptionService: TranscriptionService
    private let textInsertionService: TextInsertionService
    private var resetTask: Task<Void, Never>?

    public init(
        settingsStore: SettingsStore,
        modelDownloader: ModelDownloadService,
        permissionService: PermissionService,
        audioCapture: AudioCaptureService,
        transcriptionService: TranscriptionService,
        textInsertionService: TextInsertionService
    ) {
        self.settingsStore = settingsStore
        self.modelDownloader = modelDownloader
        self.permissionService = permissionService
        self.audioCapture = audioCapture
        self.transcriptionService = transcriptionService
        self.textInsertionService = textInsertionService
    }

    public func handleHotkey(_ phase: HotkeyPhase) {
        switch settingsStore.settings.recordingMode {
        case .holdToTalk:
            if phase == .pressed {
                beginRecording()
            } else {
                finishRecording()
            }
        case .toggle:
            guard phase == .pressed else { return }
            if case .listening = state {
                finishRecording()
            } else if case .transcribing = state {
                cancel()
            } else {
                beginRecording()
            }
        }
    }

    public func startOrStopFromMenu() {
        if case .listening = state {
            finishRecording()
        } else if case .transcribing = state {
            cancel()
        } else {
            beginRecording()
        }
    }

    public func beginRecording() {
        guard settingsStore.settings.modelDownloadState == .ready else {
            state = .error("Download a model before dictation.")
            scheduleReset()
            return
        }

        Task {
            guard await permissionService.requestMicrophoneAccess() else {
                state = .error("Microphone permission is required.")
                scheduleReset()
                return
            }

            do {
                try audioCapture.start()
                state = .listening
            } catch {
                state = .error("Could not start microphone.")
                scheduleReset()
            }
        }
    }

    public func finishRecording() {
        guard case .listening = state else { return }
        let recording = audioCapture.stop()
        state = .transcribing

        Task {
            do {
                let text = try await transcriptionService.transcribe(
                    recording,
                    language: settingsStore.settings.language,
                    model: settingsStore.settings.selectedModel,
                    modelState: settingsStore.settings.modelDownloadState
                )
                let insertionResult = textInsertionService.insert(text: text)
                switch insertionResult {
                case .inserted:
                    state = .inserted
                default:
                    state = .fallback(text)
                }
                scheduleReset()
            } catch {
                state = .error(error.localizedDescription)
                scheduleReset()
            }
        }
    }

    public func copyFallbackText() {
        guard case let .fallback(text) = state else { return }
        textInsertionService.copyToPasteboard(text)
        state = .inserted
        scheduleReset()
    }

    public func cancel() {
        resetTask?.cancel()
        audioCapture.cancel()
        state = .idle
    }

    private func scheduleReset() {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                if self?.state != .idle {
                    self?.state = .idle
                }
            }
        }
    }
}
