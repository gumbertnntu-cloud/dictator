import AppKit
import Combine
import DictatorCore
import Foundation
import SwiftUI

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
    private var settingsWindowController: SettingsWindowController?

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
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appModel: self)
        }
        settingsWindowController?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeSettings() {
        settingsWindowController?.close()
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
        let trusted = permissionService.accessibilityTrusted(prompt: true)
        guard !trusted else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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

@MainActor
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private weak var appModel: AppModel?

    init(appModel: AppModel) {
        self.appModel = appModel

        let hostingView = NSHostingView(rootView: SettingsView(appModel: appModel))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dictator Settings"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
