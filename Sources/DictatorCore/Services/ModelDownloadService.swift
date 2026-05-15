import Combine
import Foundation

@MainActor
public final class ModelDownloadService: ObservableObject {
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var deliveryStatusSummary: String?

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func refreshState(for store: SettingsStore) {
        deliveryStatusSummary = statusSummary()
        let bundledReady = BundledGigaAMPayload.isInstalled(fileManager: fileManager)
        let managedReady = markerExists(for: store.settings.selectedModel) &&
            ManagedGigaAMRuntimeInstaller.isReady(fileManager: fileManager)
        let state: ModelDownloadState = bundledReady || managedReady ? .ready : .notDownloaded
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
        deliveryStatusSummary = statusSummary()
        progress = 0

        do {
            if BundledGigaAMPayload.isBundled() {
                DictatorLog.packaging.info("Model preparation using bundled payload")
                progress = 0.1
                try BundledGigaAMPayload.installIfNeeded(fileManager: fileManager)
                progress = 0.85
            } else {
                DictatorLog.packaging.info("Model preparation using app-managed runtime setup")
                try ensureModelDirectory()
                progress = 0.1
                try await ManagedGigaAMRuntimeInstaller.ensureInstalledAndPrewarmed(fileManager: fileManager)
                progress = 0.9
            }
            let marker = markerURL(for: store.settings.selectedModel)
            let payload = "Dictator model marker for \(GigaAMRuntime.modelName)\n"
            try payload.write(to: marker, atomically: true, encoding: .utf8)
            store.updateModelState(.ready)
            progress = 1
            deliveryStatusSummary = statusSummary()
            DictatorLog.packaging.info("Model preparation marked ready")
        } catch {
            store.updateModelState(.failed)
            lastErrorMessage = error.localizedDescription
            deliveryStatusSummary = statusSummary()
            progress = 0
            DictatorLog.packaging.error("Model preparation failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    public func primaryActionTitle(for state: ModelDownloadState) -> String {
        if BundledGigaAMPayload.isBundled() {
            return state == .ready ? "Reinstall included payload" : "Install included payload"
        }

        return state == .ready ? "Repair runtime" : "Prepare Dictator"
    }

    public func runtimeDetails() -> [String] {
        guard let runtime = BundledGigaAMPayload.runtimeMetadata() else {
            return [
                "Runtime source: app-managed install",
                "Downloads uv \(ManagedGigaAMRuntimeInstaller.uvVersionLabel) and GigaAM MLX on this Mac",
                "Apple Silicon required for automatic setup"
            ]
        }

        return [
            "Runtime \(runtime.version) included in this build",
            "Source: \(runtime.source)",
            "License: \(runtime.license)",
            "Size: \(Self.formattedSize(runtime.bytes))"
        ]
    }

    public func modelDetails() -> [String] {
        guard let model = BundledGigaAMPayload.modelMetadata() else {
            return ["Model is prepared on demand the first time you download it."]
        }

        return [
            "Model \(model.version) included in this build",
            "Source: \(model.source)",
            "License: \(model.license)",
            "Size: \(Self.formattedSize(model.bytes))"
        ]
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

    private func statusSummary() -> String? {
        guard BundledGigaAMPayload.isBundled() else { return nil }
        return BundledGigaAMPayload.isInstalled(fileManager: fileManager)
            ? "Bundled runtime and model cache verified."
            : "Bundled runtime and model cache are included in this build."
    }

    private static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
