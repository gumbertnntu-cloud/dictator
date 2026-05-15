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
    private var transcriptionTask: Task<Void, Never>?
    private var insertionTarget: TextInsertionTarget?

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
        resetTask?.cancel()

        guard settingsStore.settings.modelDownloadState == .ready else {
            DictatorLog.dictation.error("Dictation blocked: model is not ready")
            state = .error("Download a model before dictation.")
            scheduleReset()
            return
        }

        guard textInsertionService.accessibilityTrusted() else {
            DictatorLog.dictation.error("Dictation blocked: Accessibility is not allowed")
            state = .error("Allow Accessibility for Dictator.")
            scheduleReset()
            return
        }

        insertionTarget = textInsertionService.captureTarget()
        guard insertionTarget != nil else {
            DictatorLog.dictation.error("Dictation blocked: no focused insertion target")
            state = .error("Put the cursor in a text field and start with the hotkey.")
            scheduleReset()
            return
        }

        Task {
            guard await permissionService.requestMicrophoneAccess() else {
                DictatorLog.dictation.error("Dictation blocked: microphone permission denied")
                state = .error("Microphone permission is required.")
                scheduleReset()
                return
            }

            do {
                try audioCapture.start()
                state = .listening
                DictatorLog.dictation.info("Dictation listening started")
            } catch {
                DictatorLog.dictation.error("Dictation failed to start microphone: \(error.localizedDescription, privacy: .public)")
                state = .error("Could not start microphone.")
                scheduleReset()
            }
        }
    }

    public func finishRecording() {
        guard case .listening = state else { return }
        let recording = audioCapture.stop()
        state = .transcribing
        DictatorLog.dictation.info("Dictation transcription started duration=\(recording.duration, privacy: .public)")

        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            let capturedTarget = self.insertionTarget
            do {
                let text = try await self.transcriptionService.transcribe(
                    recording,
                    language: self.settingsStore.settings.language,
                    model: self.settingsStore.settings.selectedModel,
                    modelState: self.settingsStore.settings.modelDownloadState
                )
                try Task.checkCancellation()
                let insertionResult = await self.textInsertionService.insert(text: text, target: capturedTarget)
                DictatorLog.dictation.info(
                    "Dictation insertion result=\(String(describing: insertionResult), privacy: .public) textLength=\((text as NSString).length, privacy: .public)"
                )
                switch insertionResult {
                case .inserted:
                    self.state = .inserted
                default:
                    self.state = .fallback(text)
                }
                self.scheduleReset()
            } catch is CancellationError {
                DictatorLog.dictation.info("Dictation transcription cancelled")
                self.state = .idle
                self.insertionTarget = nil
            } catch GigaAMRuntimeError.cancelled {
                DictatorLog.dictation.info("Dictation transcription cancelled (runtime)")
                self.state = .idle
                self.insertionTarget = nil
            } catch GigaAMRuntimeError.transcriptEmpty {
                DictatorLog.dictation.info("Dictation transcription empty — inserting placeholder dash")
                await self.insertPlaceholder(target: capturedTarget)
            } catch TranscriptionError.emptyRecording {
                DictatorLog.dictation.info("Dictation recording empty — inserting placeholder dash")
                await self.insertPlaceholder(target: capturedTarget)
            } catch {
                DictatorLog.dictation.error("Dictation failed: \(error.localizedDescription, privacy: .public)")
                self.state = .error(error.localizedDescription)
                self.scheduleReset()
            }
        }
    }

    private func insertPlaceholder(target: TextInsertionTarget?) async {
        let placeholder = "-"
        let result = await textInsertionService.insert(text: placeholder, target: target)
        switch result {
        case .inserted:
            state = .inserted
        default:
            state = .fallback(placeholder)
        }
        scheduleReset()
    }

    public func copyFallbackText() {
        guard case let .fallback(text) = state else { return }
        textInsertionService.copyToPasteboard(text)
        state = .inserted
        scheduleReset()
    }

    public func caretBoundsOnScreen() -> CGRect? {
        textInsertionService.caretBounds(target: insertionTarget)
    }

    public func cancel() {
        resetTask?.cancel()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        audioCapture.cancel()
        insertionTarget = nil
        state = .idle
        DictatorLog.dictation.info("Dictation cancelled")
    }

    private func scheduleReset() {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                if self?.state != .idle {
                    self?.state = .idle
                    self?.insertionTarget = nil
                }
            }
        }
    }
}
