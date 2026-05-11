import AppKit
import DictatorCore
import SwiftUI

@main
struct DictatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra {
            Button(menuPrimaryTitle) {
                appModel.startOrStopDictation()
            }
            .keyboardShortcut("d")

            Button("Settings") {
                appModel.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            ModelMenuStatusView(appModel: appModel)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: menuIconName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appModel: appModel)
        }
    }

    private var menuPrimaryTitle: String {
        switch appModel.dictationController.state {
        case .listening: "Stop Dictation"
        case .transcribing: "Cancel"
        default: "Start Dictation"
        }
    }

    private var menuIconName: String {
        switch appModel.dictationController.state {
        case .listening: "mic.fill"
        case .transcribing: "waveform.badge.magnifyingglass"
        case .error: "exclamationmark.triangle.fill"
        default: "mic"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct ModelMenuStatusView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        Text("Model: \(appModel.settingsStore.settings.modelDownloadState.title)")
        Text("Mode: \(appModel.settingsStore.settings.recordingMode.title)")
    }
}
