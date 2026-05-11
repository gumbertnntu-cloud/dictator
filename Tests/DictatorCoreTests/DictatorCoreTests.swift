import Foundation
import Testing
@testable import DictatorCore

@Suite("DictatorCore")
struct DictatorCoreTests {
    @Test func defaultSettingsMatchV1Plan() {
        let settings = DictationSettings()

        #expect(settings.language == .ru)
        #expect(settings.selectedModel == .base)
        #expect(settings.modelDownloadState == .notDownloaded)
        #expect(settings.recordingMode == .holdToTalk)
        #expect(settings.hotkey == .defaultHotkey)
    }

    @Test func settingsRoundTrip() throws {
        let settings = DictationSettings(
            language: .en,
            selectedModel: .small,
            modelDownloadState: .ready,
            recordingMode: .toggle,
            hotkey: Hotkey(keyCode: 8, modifiers: 4_096, displayName: "⌃C"),
            launchAtLogin: false
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DictationSettings.self, from: data)

        #expect(decoded == settings)
    }

    @Test func audioRecordingDuration() {
        let recording = AudioRecording(samples: Array(repeating: 0.1, count: 44_100), sampleRate: 44_100)

        #expect(abs(recording.duration - 1) < 0.001)
    }
}
