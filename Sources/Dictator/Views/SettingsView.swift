import DictatorCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appModel: AppModel
    @State private var showSavedToast = false
    @State private var toastDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 18) {
                header
                ModelSection(
                    settingsStore: appModel.settingsStore,
                    modelDownloader: appModel.modelDownloader,
                    downloadAction: appModel.downloadSelectedModel
                )
                HotkeySection(appModel: appModel)
                PressModeSection(settingsStore: appModel.settingsStore)
                PrivacySection(appModel: appModel)
                footer
            }
            .padding(22)
            .frame(width: 420)

            if showSavedToast {
                SavedToast()
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showSavedToast)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dictator")
                .font(.title2.weight(.semibold))
            Text("Build \(AppBuild.label)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Save") {
                triggerSavedFeedback()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
    }

    private func triggerSavedFeedback() {
        toastDismissTask?.cancel()
        showSavedToast = true
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            showSavedToast = false
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            appModel.closeSettings()
        }
    }
}

private struct SavedToast: View {
    var body: some View {
        Label("Сохранено", systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.92), in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
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

            ForEach(modelDownloader.runtimeDetails(), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(modelDownloader.modelDetails(), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settingsStore.settings.selectedModel.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(settingsStore.settings.modelDownloadState.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(modelStateColor)
                    if let summary = modelDownloader.deliveryStatusSummary {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(modelDownloader.primaryActionTitle(for: settingsStore.settings.modelDownloadState)) {
                    downloadAction()
                }
                .disabled(settingsStore.settings.modelDownloadState == .downloading)
            }

            if settingsStore.settings.modelDownloadState == .downloading {
                ProgressView(value: modelDownloader.progress)
                    .progressViewStyle(.linear)
            }

            if settingsStore.settings.modelDownloadState == .failed,
               let message = modelDownloader.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
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
