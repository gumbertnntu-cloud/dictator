import DictatorCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            LanguageSection(settingsStore: appModel.settingsStore)
            ModelSection(
                settingsStore: appModel.settingsStore,
                modelDownloader: appModel.modelDownloader,
                downloadAction: appModel.downloadSelectedModel
            )
            HotkeySection(appModel: appModel)
            PressModeSection(settingsStore: appModel.settingsStore)
            PrivacySection(appModel: appModel)
        }
        .padding(22)
        .frame(width: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dictator")
                .font(.title2.weight(.semibold))
            Text("Local dictation for the active macOS text field.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LanguageSection: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        SettingsCard(title: "Language", systemImage: "globe") {
            Picker("Language", selection: Binding(
                get: { settingsStore.settings.language },
                set: { settingsStore.updateLanguage($0) }
            )) {
                ForEach(DictationLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private struct ModelSection: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var modelDownloader: ModelDownloadService
    let downloadAction: () -> Void

    var body: some View {
        SettingsCard(title: "Model", systemImage: "square.and.arrow.down") {
            Picker("Model", selection: Binding(
                get: { settingsStore.settings.selectedModel },
                set: { settingsStore.updateSelectedModel($0) }
            )) {
                ForEach(ModelOption.allCases) { model in
                    Text(model.title).tag(model)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settingsStore.settings.selectedModel.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(settingsStore.settings.modelDownloadState.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(modelStateColor)
                }
                Spacer()
                Button(downloadButtonTitle) {
                    downloadAction()
                }
                .disabled(settingsStore.settings.modelDownloadState == .downloading)
            }

            if settingsStore.settings.modelDownloadState == .downloading {
                ProgressView(value: modelDownloader.progress)
                    .progressViewStyle(.linear)
            }
        }
    }

    private var downloadButtonTitle: String {
        settingsStore.settings.modelDownloadState == .ready ? "Download again" : "Download"
    }

    private var modelStateColor: Color {
        switch settingsStore.settings.modelDownloadState {
        case .ready: .green
        case .failed: .red
        case .downloading: .blue
        case .notDownloaded: .secondary
        }
    }
}

private struct HotkeySection: View {
    @ObservedObject var appModel: AppModel
    @State private var isRecording = false

    var body: some View {
        SettingsCard(title: "Hotkey", systemImage: "keyboard") {
            HStack(spacing: 10) {
                Text(isRecording ? "Press shortcut..." : appModel.settingsStore.settings.hotkey.displayName)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Button(isRecording ? "Cancel" : "Record") {
                    isRecording.toggle()
                }

                Button("Reset") {
                    appModel.settingsStore.resetHotkey()
                }
            }
            .background(
                HotkeyCaptureView(isRecording: $isRecording) { hotkey in
                    appModel.updateHotkey(hotkey)
                    isRecording = false
                }
            )

            if let message = appModel.hotkeyRegistrationMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct PressModeSection: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        SettingsCard(title: "Press Mode", systemImage: "hand.tap") {
            Picker("Press Mode", selection: Binding(
                get: { settingsStore.settings.recordingMode },
                set: { settingsStore.updateRecordingMode($0) }
            )) {
                ForEach(RecordingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private struct PrivacySection: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        SettingsCard(title: "Privacy", systemImage: "lock.shield") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Audio and transcripts are not saved.")
                        .font(.callout)
                    Text("Accessibility is used only to insert text into the focused field.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(appModel.accessibilityTrusted() ? "Allowed" : "Allow") {
                    appModel.requestAccessibility()
                }
                .disabled(appModel.accessibilityTrusted())
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
