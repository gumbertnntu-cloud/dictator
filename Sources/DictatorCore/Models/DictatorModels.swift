import Foundation

public enum RecordingMode: String, CaseIterable, Codable, Identifiable {
    case holdToTalk
    case toggle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .holdToTalk: "Hold to talk"
        case .toggle: "Toggle"
        }
    }
}

public enum DictationLanguage: String, CaseIterable, Codable, Identifiable {
    case ru
    case en

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ru: "Русский"
        case .en: "English"
        }
    }

    public var placeholderTranscript: String {
        switch self {
        case .ru: "Тестовая локальная расшифровка Dictator."
        case .en: "Dictator local transcription test."
        }
    }
}

public enum ModelDownloadState: String, CaseIterable, Codable, Identifiable {
    case notDownloaded
    case downloading
    case ready
    case failed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notDownloaded: "Not downloaded"
        case .downloading: "Downloading"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }
}

public enum DictationState: Equatable {
    case idle
    case listening
    case transcribing
    case inserted
    case fallback(String)
    case error(String)

    public var isVisibleInBubble: Bool {
        switch self {
        case .idle: false
        default: true
        }
    }
}

public enum InsertionResult: Equatable {
    case inserted
    case unsupportedTarget
    case secureField
    case focusLost
    case failed
}

public enum ModelOption: String, CaseIterable, Codable, Identifiable {
    case tiny
    case base
    case small

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tiny: "Whisper Tiny"
        case .base: "Whisper Base"
        case .small: "Whisper Small"
        }
    }

    public var subtitle: String {
        switch self {
        case .tiny: "Fastest, lowest accuracy"
        case .base: "Balanced default"
        case .small: "Better quality, slower on Intel"
        }
    }
}

public struct Hotkey: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var displayName: String

    public init(keyCode: UInt32, modifiers: UInt32, displayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
    }

    public static let defaultHotkey = Hotkey(
        keyCode: 49,
        modifiers: 4_096 + 2_048,
        displayName: "⌃⌥Space"
    )
}

public struct DictationSettings: Codable, Equatable {
    public var language: DictationLanguage
    public var selectedModel: ModelOption
    public var modelDownloadState: ModelDownloadState
    public var recordingMode: RecordingMode
    public var hotkey: Hotkey
    public var launchAtLogin: Bool

    public init(
        language: DictationLanguage = .ru,
        selectedModel: ModelOption = .base,
        modelDownloadState: ModelDownloadState = .notDownloaded,
        recordingMode: RecordingMode = .holdToTalk,
        hotkey: Hotkey = .defaultHotkey,
        launchAtLogin: Bool = false
    ) {
        self.language = language
        self.selectedModel = selectedModel
        self.modelDownloadState = modelDownloadState
        self.recordingMode = recordingMode
        self.hotkey = hotkey
        self.launchAtLogin = launchAtLogin
    }
}

public struct AudioRecording: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let duration: TimeInterval

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.duration = sampleRate > 0 ? Double(samples.count) / sampleRate : 0
    }
}
