import AppKit
import Combine
import DictatorCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var hotkeyRegistrationMessage: String?

    let settingsStore: SettingsStore
    let modelDownloader: ModelDownloadService
    let audioCapture: AudioCaptureService
    let dictationController: DictationController

    private let permissionService: PermissionService
    private let textInsertionService: TextInsertionService
    private let hotkeyService: HotkeyService
    private var cancellables: Set<AnyCancellable> = []
    private var bubbleController: StatusBubbleWindowController?

    init() {
        settingsStore = SettingsStore()
        modelDownloader = ModelDownloadService()
        audioCapture = AudioCaptureService()
        permissionService = PermissionService()
        textInsertionService = TextInsertionService()
        hotkeyService = HotkeyService()

        dictationController = DictationController(
            settingsStore: settingsStore,
            modelDownloader: modelDownloader,
            permissionService: permissionService,
            audioCapture: audioCapture,
            transcriptionService: TranscriptionService(),
            textInsertionService: textInsertionService
        )

        modelDownloader.refreshState(for: settingsStore)
        registerHotkey(settingsStore.settings.hotkey)
        observeSettings()
        observeBubbleState()
    }

    func startOrStopDictation() {
        dictationController.startOrStopFromMenu()
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func downloadSelectedModel() {
        Task {
            await modelDownloader.downloadSelectedModel(for: settingsStore)
        }
    }

    func updateHotkey(_ hotkey: Hotkey) {
        settingsStore.updateHotkey(hotkey)
    }

    func requestAccessibility() {
        _ = permissionService.accessibilityTrusted(prompt: true)
    }

    func accessibilityTrusted() -> Bool {
        permissionService.accessibilityTrusted(prompt: false)
    }

    private func observeSettings() {
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        modelDownloader.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        dictationController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .map(\.hotkey)
            .removeDuplicates()
            .sink { [weak self] hotkey in
                self?.registerHotkey(hotkey)
            }
            .store(in: &cancellables)
    }

    private func observeBubbleState() {
        bubbleController = StatusBubbleWindowController(controller: dictationController, audioCapture: audioCapture)
    }

    private func registerHotkey(_ hotkey: Hotkey) {
        let didRegister = hotkeyService.register(hotkey) { [weak self] phase in
            Task { @MainActor in
                self?.dictationController.handleHotkey(phase)
            }
        }
        hotkeyRegistrationMessage = didRegister ? nil : "This shortcut is already used by macOS or another app."
    }
}
