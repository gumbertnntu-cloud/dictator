import CryptoKit
import Darwin
import Foundation

struct BundledGigaAMPayloadManifest: Codable {
    struct Component: Codable {
        let relativePath: String
        let version: String
        let source: String
        let license: String
        let bytes: Int64
        let fingerprint: String
    }

    let schemaVersion: Int
    let runtime: Component
    let model: Component
}

enum BundledGigaAMPayloadError: Error, LocalizedError {
    case unsupportedArchitecture
    case manifestMissing
    case componentMissing(String)
    case fingerprintMismatch(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture:
            "This bundled speech runtime currently supports Apple Silicon only."
        case .manifestMissing:
            "This build does not include a bundled speech runtime payload."
        case let .componentMissing(name):
            "Bundled \(name) files are missing from the app package."
        case let .fingerprintMismatch(name):
            "Bundled \(name) files failed integrity verification."
        }
    }
}

enum BundledGigaAMPayload {
    private static let payloadDirectoryName = "GigaAMPayload"

    static func manifest(bundle: Bundle = .main) -> BundledGigaAMPayloadManifest? {
        guard let manifestURL = payloadRootURL(bundle: bundle)?.appendingPathComponent("manifest.json"),
              let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }

        return try? JSONDecoder().decode(BundledGigaAMPayloadManifest.self, from: data)
    }

    static func isBundled(bundle: Bundle = .main) -> Bool {
        manifest(bundle: bundle) != nil
    }

    static func isInstalled(fileManager: FileManager = .default, bundle: Bundle = .main) -> Bool {
        guard let manifest = manifest(bundle: bundle) else { return false }

        let runtimeURL = installedRuntimeURL(fileManager: fileManager)
        let modelURL = installedModelCacheURL(fileManager: fileManager)

        guard fileManager.fileExists(atPath: runtimeURL.path),
              fileManager.fileExists(atPath: modelURL.path) else {
            return false
        }

        return matchesFingerprint(at: runtimeURL, expected: manifest.runtime.fingerprint) &&
            matchesFingerprint(at: modelURL, expected: manifest.model.fingerprint)
    }

    static func installIfNeeded(fileManager: FileManager = .default, bundle: Bundle = .main) throws {
        guard let manifest = manifest(bundle: bundle) else {
            DictatorLog.packaging.error("Bundled GigaAM payload manifest is missing")
            throw BundledGigaAMPayloadError.manifestMissing
        }

        guard ProcessInfo.processInfo.machineArchitecture == "arm64" else {
            DictatorLog.packaging.error(
                "Bundled GigaAM payload rejected unsupported architecture=\(ProcessInfo.processInfo.machineArchitecture, privacy: .public)"
            )
            throw BundledGigaAMPayloadError.unsupportedArchitecture
        }

        DictatorLog.packaging.info(
            "Bundled GigaAM payload install started runtimeVersion=\(manifest.runtime.version, privacy: .public) modelVersion=\(manifest.model.version, privacy: .public)"
        )
        let runtimeSource = try sourceURL(for: manifest.runtime, bundle: bundle)
        let modelSource = try sourceURL(for: manifest.model, bundle: bundle)

        let installRoot = try installedAssetsRoot(fileManager: fileManager)
        try fileManager.createDirectory(at: installRoot, withIntermediateDirectories: true)

        try installComponent(
            named: "runtime",
            source: runtimeSource,
            destination: installedRuntimeURL(fileManager: fileManager),
            expectedFingerprint: manifest.runtime.fingerprint,
            fileManager: fileManager
        )

        try installComponent(
            named: "model",
            source: modelSource,
            destination: installedModelCacheURL(fileManager: fileManager),
            expectedFingerprint: manifest.model.fingerprint,
            fileManager: fileManager
        )
        DictatorLog.packaging.info("Bundled GigaAM payload install finished")
    }

    static func runtimeMetadata(bundle: Bundle = .main) -> BundledGigaAMPayloadManifest.Component? {
        manifest(bundle: bundle)?.runtime
    }

    static func modelMetadata(bundle: Bundle = .main) -> BundledGigaAMPayloadManifest.Component? {
        manifest(bundle: bundle)?.model
    }

    static func installedRuntimeExecutableSearchDirectories(fileManager: FileManager = .default) -> [URL] {
        let runtimeURL = installedRuntimeURL(fileManager: fileManager)
        return [
            runtimeURL.appendingPathComponent("bin", isDirectory: true),
            runtimeURL
        ]
    }

    static func huggingFaceHomeURL(fileManager: FileManager = .default) -> URL {
        installedModelCacheURL(fileManager: fileManager)
    }

    static func huggingFaceHubCacheURL(fileManager: FileManager = .default) -> URL {
        huggingFaceHomeURL(fileManager: fileManager).appendingPathComponent("hub", isDirectory: true)
    }

    private static func sourceURL(
        for component: BundledGigaAMPayloadManifest.Component,
        bundle: Bundle
    ) throws -> URL {
        guard let root = payloadRootURL(bundle: bundle) else {
            throw BundledGigaAMPayloadError.manifestMissing
        }

        let url = root.appendingPathComponent(component.relativePath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            DictatorLog.packaging.error(
                "Bundled GigaAM payload component missing relativePath=\(component.relativePath, privacy: .public)"
            )
            throw BundledGigaAMPayloadError.componentMissing(component.relativePath)
        }

        return url
    }

    private static func installComponent(
        named: String,
        source: URL,
        destination: URL,
        expectedFingerprint: String,
        fileManager: FileManager
    ) throws {
        guard matchesFingerprint(at: source, expected: expectedFingerprint) else {
            DictatorLog.packaging.error("Bundled GigaAM payload source fingerprint mismatch component=\(named, privacy: .public)")
            throw BundledGigaAMPayloadError.fingerprintMismatch(named)
        }

        if fileManager.fileExists(atPath: destination.path) {
            if matchesFingerprint(at: destination, expected: expectedFingerprint) {
                DictatorLog.packaging.info("Bundled GigaAM payload component already installed component=\(named, privacy: .public)")
                return
            }
            DictatorLog.packaging.info("Bundled GigaAM payload component reinstalling component=\(named, privacy: .public)")
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: source, to: destination)

        guard matchesFingerprint(at: destination, expected: expectedFingerprint) else {
            DictatorLog.packaging.error("Bundled GigaAM payload installed fingerprint mismatch component=\(named, privacy: .public)")
            throw BundledGigaAMPayloadError.fingerprintMismatch(named)
        }
        DictatorLog.packaging.info("Bundled GigaAM payload component installed component=\(named, privacy: .public)")
    }

    private static func payloadRootURL(bundle: Bundle) -> URL? {
        bundle.resourceURL?.appendingPathComponent(payloadDirectoryName, isDirectory: true)
    }

    private static func installedAssetsRoot(fileManager: FileManager) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return applicationSupport.appendingPathComponent("Dictator/BundledAssets", isDirectory: true)
    }

    private static func installedRuntimeURL(fileManager: FileManager) -> URL {
        do {
            return try installedAssetsRoot(fileManager: fileManager)
                .appendingPathComponent("runtime", isDirectory: true)
        } catch {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Dictator-BundledRuntime", isDirectory: true)
        }
    }

    private static func installedModelCacheURL(fileManager: FileManager) -> URL {
        do {
            return try installedAssetsRoot(fileManager: fileManager)
                .appendingPathComponent("hf-home", isDirectory: true)
        } catch {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Dictator-HFHome", isDirectory: true)
        }
    }

    private static func matchesFingerprint(at url: URL, expected: String) -> Bool {
        (try? fingerprint(of: url)) == expected
    }

    private static func fingerprint(of url: URL) throws -> String {
        var hasher = SHA256()
        try updateHasher(&hasher, with: url, root: url)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func updateHasher(_ hasher: inout SHA256, with url: URL, root: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        let relativePath = url.path.replacingOccurrences(of: root.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        hasher.update(data: Data(relativePath.utf8))

        if values.isDirectory == true {
            hasher.update(data: Data("/".utf8))
            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            for child in children {
                try updateHasher(&hasher, with: child, root: root)
            }
            return
        }

        hasher.update(data: try Data(contentsOf: url))
    }
}

private extension ProcessInfo {
    var machineArchitecture: String {
        if let value = environment["PROCESSOR_ARCHITECTURE"], !value.isEmpty {
            return value
        }
        var system = utsname()
        guard uname(&system) == 0 else { return "" }
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 64) { pointer in
                String(cString: pointer)
            }
        }
    }
}
