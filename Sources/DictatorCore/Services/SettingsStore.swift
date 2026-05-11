import Combine
import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var settings: DictationSettings

    private let defaults: UserDefaults
    private let key = "dictator.settings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(DictationSettings.self, from: data) {
            self.settings = Self.migrated(decoded)
        } else {
            self.settings = DictationSettings()
        }
    }

    public func updateLanguage(_ language: DictationLanguage) {
        settings.language = language
        save()
    }

    public func updateSelectedModel(_ model: ModelOption) {
        settings.selectedModel = model
        settings.modelDownloadState = .notDownloaded
        save()
    }

    public func updateModelState(_ state: ModelDownloadState) {
        settings.modelDownloadState = state
        save()
    }

    public func updateRecordingMode(_ mode: RecordingMode) {
        settings.recordingMode = mode
        save()
    }

    public func updateHotkey(_ hotkey: Hotkey) {
        settings.hotkey = hotkey
        save()
    }

    public func resetHotkey() {
        updateHotkey(.defaultHotkey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    private static func migrated(_ settings: DictationSettings) -> DictationSettings {
        guard settings.selectedModel != .gigaamV3E2ERNNT else { return settings }

        return DictationSettings(
            language: settings.language,
            selectedModel: .gigaamV3E2ERNNT,
            modelDownloadState: .notDownloaded,
            recordingMode: settings.recordingMode,
            hotkey: settings.hotkey,
            launchAtLogin: settings.launchAtLogin
        )
    }
}
