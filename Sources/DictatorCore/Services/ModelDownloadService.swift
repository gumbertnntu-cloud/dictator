import Combine
import Foundation

@MainActor
public final class ModelDownloadService: ObservableObject {
    @Published public private(set) var progress: Double = 0

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func refreshState(for store: SettingsStore) {
        let state: ModelDownloadState = markerExists(for: store.settings.selectedModel) ? .ready : .notDownloaded
        store.updateModelState(state)
    }

    public func downloadSelectedModel(for store: SettingsStore) async {
        store.updateModelState(.downloading)
        progress = 0

        do {
            try ensureModelDirectory()
            for step in 1...20 {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 80_000_000)
                progress = Double(step) / 20.0
            }
            let marker = markerURL(for: store.settings.selectedModel)
            let payload = "Dictator v1 model marker for \(store.settings.selectedModel.rawValue)\n"
            try payload.write(to: marker, atomically: true, encoding: .utf8)
            store.updateModelState(.ready)
        } catch {
            store.updateModelState(.failed)
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
