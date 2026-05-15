import AVFoundation
import Foundation
import Testing
@testable import DictatorCore

@Suite("DictatorCore")
struct DictatorCoreTests {
    @Test func defaultSettingsMatchV1Plan() {
        let settings = DictationSettings()

        #expect(settings.language == .ru)
        #expect(settings.selectedModel == .gigaamV3E2ERNNT)
        #expect(settings.modelDownloadState == .notDownloaded)
        #expect(settings.recordingMode == .holdToTalk)
        #expect(settings.hotkey == .defaultHotkey)
    }

    @Test func settingsRoundTrip() throws {
        let settings = DictationSettings(
            language: .en,
            selectedModel: .gigaamV3E2ERNNT,
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

    @Test func threeMinuteRecordingSplitsIntoTwentySecondChunks() {
        let sampleRate = 16_000.0
        let recording = AudioRecording(
            samples: Array(repeating: 0.1, count: Int(sampleRate * 180)),
            sampleRate: sampleRate
        )
        let chunks = recording.chunks(maxDuration: 20)

        #expect(abs(recording.duration - 180) < 0.001)
        #expect(chunks.count == 9)
        #expect(chunks.allSatisfy { $0.duration <= 20.001 })
        #expect(abs(chunks.reduce(0) { $0 + $1.duration } - recording.duration) < 0.001)
    }

    @Test func functionKeyCanBeStoredAsModifierOnlyHotkey() throws {
        let hotkey = Hotkey(
            keyCode: Hotkey.modifierOnlyKeyCode,
            modifiers: Hotkey.functionModifier,
            displayName: "Fn"
        )

        let data = try JSONEncoder().encode(hotkey)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)

        #expect(decoded == hotkey)
        #expect(decoded.isModifierOnly)
    }

    @Test func managedRuntimeIntegrationInstallsFFmpegShim() async throws {
        guard ProcessInfo.processInfo.environment["DICTATOR_RUN_MANAGED_RUNTIME_INTEGRATION"] == "1" else {
            return
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dictator-ManagedRuntime-Test-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            unsetenv("DICTATOR_MANAGED_RUNTIME_ROOT")
        }
        setenv("DICTATOR_MANAGED_RUNTIME_ROOT", root.path, 1)

        try await ManagedGigaAMRuntimeInstaller.ensureInstalled()

        let toolBin = root.appendingPathComponent("tool-bin", isDirectory: true)
        let gigaAM = toolBin.appendingPathComponent("gigaam-mlx")
        let ffmpeg = toolBin.appendingPathComponent("ffmpeg")

        #expect(FileManager.default.isExecutableFile(atPath: gigaAM.path))
        #expect(FileManager.default.isExecutableFile(atPath: ffmpeg.path))
        #expect(ManagedGigaAMRuntimeInstaller.isReady())

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func integrationThreeMinuteWavTranscribesEndToEnd() async throws {
        guard let wavPath = ProcessInfo.processInfo.environment["DICTATOR_TEST_WAV"] else {
            return
        }
        let url = URL(fileURLWithPath: wavPath)
        let recording = try Self.loadRecording(from: url)
        #expect(recording.duration >= 60)

        let started = Date()
        let service = TranscriptionService()
        let transcript = try await service.transcribe(
            recording,
            language: .ru,
            model: .gigaamV3E2ERNNT,
            modelState: .ready
        )
        let elapsed = Date().timeIntervalSince(started)
        let preview = String(transcript.prefix(160))
        print("[integration] duration=\(recording.duration)s elapsed=\(elapsed)s textLen=\(transcript.count)\npreview: \(preview)")

        #expect(!transcript.isEmpty)
        #expect(transcript.count >= 200)
    }

    private static func loadRecording(from url: URL) throws -> AudioRecording {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "DictatorCoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "PCM buffer allocation failed"])
        }
        try file.read(into: buffer)
        guard let floatChannel = buffer.floatChannelData?[0] else {
            throw NSError(domain: "DictatorCoreTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "WAV has no float channel data"])
        }
        let samples = Array(UnsafeBufferPointer(start: floatChannel, count: Int(buffer.frameLength)))
        return AudioRecording(samples: samples, sampleRate: format.sampleRate)
    }
}
