import Combine
import Foundation

@MainActor
public final class ModelDownloadService: ObservableObject {
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var lastErrorMessage: String?

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func refreshState(for store: SettingsStore) {
        let state: ModelDownloadState = markerExists(for: store.settings.selectedModel) ? .ready : .notDownloaded
        store.updateModelState(state)
    }

    public func downloadSelectedModel(for store: SettingsStore) async {
        guard store.settings.selectedModel == .gigaamV3E2ERNNT else {
            store.updateModelState(.failed)
            lastErrorMessage = "Unsupported model."
            return
        }

        store.updateModelState(.downloading)
        lastErrorMessage = nil
        progress = 0

        do {
            try ensureModelDirectory()
            progress = 0.1
            try await GigaAMRuntime.prewarm()
            progress = 0.9
            let marker = markerURL(for: store.settings.selectedModel)
            let payload = "Dictator model marker for \(GigaAMRuntime.modelName)\n"
            try payload.write(to: marker, atomically: true, encoding: .utf8)
            store.updateModelState(.ready)
            progress = 1
        } catch {
            store.updateModelState(.failed)
            lastErrorMessage = error.localizedDescription
            progress = 0
        }
    }

    public func modelDirectory() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Dictator/Models", isDirectory: true)
    }

    private func ensureModelDirectory() throws {
        try fileManager.createDirectory(at: modelDirectory(), withIntermediateDirectories: true)
    }

    private func markerURL(for model: ModelOption) -> URL {
        do {
            return try modelDirectory().appendingPathComponent("\(model.rawValue).ready")
        } catch {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(model.rawValue).ready")
        }
    }

    private func markerExists(for model: ModelOption) -> Bool {
        fileManager.fileExists(atPath: markerURL(for: model).path)
    }
}
