import Darwin
import Foundation

enum ManagedGigaAMRuntimeInstallerError: Error, LocalizedError {
    case unsupportedArchitecture
    case commandFailed(String)
    case ffmpegMissingAfterInstall
    case uvMissingAfterInstall
    case runtimeMissingAfterInstall

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture:
            "Automatic runtime setup currently supports Apple Silicon Macs only."
        case let .commandFailed(message):
            message
        case .ffmpegMissingAfterInstall:
            "ffmpeg helper was installed, but the app could not find it."
        case .uvMissingAfterInstall:
            "uv was installed, but the app could not find the uv executable."
        case .runtimeMissingAfterInstall:
            "GigaAM MLX was installed, but the app could not find the runtime executable."
        }
    }
}

enum ManagedGigaAMRuntimeInstaller {
    private static let uvVersion = "0.11.11"
    private static let gigaAMMLXSource = "git+https://github.com/aystream/gigaam-mlx.git"
    static let uvVersionLabel = uvVersion

    static func runtimeExecutableSearchDirectories(fileManager: FileManager = .default) -> [URL] {
        [
            toolBinURL(fileManager: fileManager),
            uvBinURL(fileManager: fileManager)
        ]
    }

    static func isInstalled(fileManager: FileManager = .default) -> Bool {
        FileManager.default.isExecutableFile(
            atPath: toolBinURL(fileManager: fileManager).appendingPathComponent("gigaam-mlx").path
        )
    }

    static func isReady(fileManager: FileManager = .default) -> Bool {
        isInstalled(fileManager: fileManager) &&
            ffmpegShimURL(fileManager: fileManager).isExecutableFile &&
            hasImageIOFFmpeg(fileManager: fileManager)
    }

    static func ensureInstalled(fileManager: FileManager = .default) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard ProcessInfo.processInfo.machineArchitecture == "arm64" else {
                DictatorLog.packaging.error(
                    "Managed runtime setup rejected unsupported architecture=\(ProcessInfo.processInfo.machineArchitecture, privacy: .public)"
                )
                throw ManagedGigaAMRuntimeInstallerError.unsupportedArchitecture
            }

            DictatorLog.packaging.info("Managed runtime setup started")
            try ensureDirectories(fileManager: fileManager)
            let uvURL = try installUVIfNeeded(fileManager: fileManager)
            try installGigaAMMLXIfNeeded(uvURL: uvURL, fileManager: fileManager)
            try installFFmpegShimIfNeeded(fileManager: fileManager)
            guard isInstalled(fileManager: fileManager) else {
                DictatorLog.packaging.error("Managed runtime setup could not find gigaam-mlx after install")
                throw ManagedGigaAMRuntimeInstallerError.runtimeMissingAfterInstall
            }
            guard isReady(fileManager: fileManager) else {
                DictatorLog.packaging.error("Managed runtime setup finished but readiness check failed")
                throw ManagedGigaAMRuntimeInstallerError.ffmpegMissingAfterInstall
            }
            DictatorLog.packaging.info("Managed runtime setup finished")
        }.value
    }

    static func ensureInstalledAndPrewarmed(fileManager: FileManager = .default) async throws {
        try await ensureInstalled(fileManager: fileManager)
        try await GigaAMRuntime.prewarm()
    }

    static func managedEnvironment(fileManager: FileManager = .default) -> [String: String] {
        [
            "UV_CACHE_DIR": uvCacheURL(fileManager: fileManager).path,
            "UV_TOOL_BIN_DIR": toolBinURL(fileManager: fileManager).path,
            "UV_TOOL_DIR": toolDirURL(fileManager: fileManager).path,
            "UV_PYTHON_INSTALL_DIR": pythonDirURL(fileManager: fileManager).path,
            "HF_HOME": hfHomeURL(fileManager: fileManager).path,
            "HF_HUB_CACHE": hfHomeURL(fileManager: fileManager).appendingPathComponent("hub", isDirectory: true).path,
            "XDG_CACHE_HOME": xdgCacheURL(fileManager: fileManager).path,
            "XDG_DATA_HOME": xdgDataURL(fileManager: fileManager).path,
            "UV_NO_MODIFY_PATH": "1",
            "PYTHONUNBUFFERED": "1",
            "HF_HUB_DISABLE_PROGRESS_BARS": "1"
        ]
    }

    private static func installUVIfNeeded(fileManager: FileManager) throws -> URL {
        let uvURL = uvBinURL(fileManager: fileManager).appendingPathComponent("uv")
        if fileManager.isExecutableFile(atPath: uvURL.path) {
            DictatorLog.packaging.info("Managed uv already installed")
            return uvURL
        }

        DictatorLog.packaging.info("Managed uv install started version=\(uvVersion, privacy: .public)")
        let scriptURL = try downloadUVInstaller(fileManager: fileManager)
        try runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [scriptURL.path],
            environment: [
                "UV_UNMANAGED_INSTALL": uvBinURL(fileManager: fileManager).path,
                "UV_NO_MODIFY_PATH": "1"
            ],
            workDirectory: managedRootURL(fileManager: fileManager)
        )

        guard fileManager.isExecutableFile(atPath: uvURL.path) else {
            DictatorLog.packaging.error("Managed uv install finished without uv executable")
            throw ManagedGigaAMRuntimeInstallerError.uvMissingAfterInstall
        }

        DictatorLog.packaging.info("Managed uv install finished")
        return uvURL
    }

    private static func installGigaAMMLXIfNeeded(uvURL: URL, fileManager: FileManager) throws {
        if isInstalled(fileManager: fileManager), hasImageIOFFmpeg(fileManager: fileManager) {
            DictatorLog.packaging.info("Managed gigaam-mlx already installed")
            return
        }

        DictatorLog.packaging.info("Managed gigaam-mlx install started")
        try runProcess(
            executableURL: uvURL,
            arguments: [
                "tool", "install", gigaAMMLXSource,
                "--force",
                "--python", "3.12",
                "--with", "imageio-ffmpeg"
            ],
            environment: managedEnvironment(fileManager: fileManager),
            workDirectory: managedRootURL(fileManager: fileManager)
        )
        DictatorLog.packaging.info("Managed gigaam-mlx install finished")
    }

    private static func installFFmpegShimIfNeeded(fileManager: FileManager) throws {
        let shimURL = ffmpegShimURL(fileManager: fileManager)
        let pythonURL = gigaAMToolPythonURL(fileManager: fileManager)
        guard fileManager.isExecutableFile(atPath: pythonURL.path) else {
            DictatorLog.packaging.error("Managed ffmpeg shim missing tool python")
            throw ManagedGigaAMRuntimeInstallerError.ffmpegMissingAfterInstall
        }

        let script = """
        #!/bin/sh
        exec "\(pythonURL.path)" -c 'import os, sys, imageio_ffmpeg; exe = imageio_ffmpeg.get_ffmpeg_exe(); os.execv(exe, [exe] + sys.argv[1:])' "$@"
        """
        try script.write(to: shimURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimURL.path)
        guard shimURL.isExecutableFile else {
            DictatorLog.packaging.error("Managed ffmpeg shim was written but is not executable")
            throw ManagedGigaAMRuntimeInstallerError.ffmpegMissingAfterInstall
        }
        try runProcess(
            executableURL: shimURL,
            arguments: ["-version"],
            environment: managedEnvironment(fileManager: fileManager),
            workDirectory: managedRootURL(fileManager: fileManager)
        )
        DictatorLog.packaging.info("Managed ffmpeg shim installed")
    }

    private static func hasImageIOFFmpeg(fileManager: FileManager) -> Bool {
        let pythonURL = gigaAMToolPythonURL(fileManager: fileManager)
        guard pythonURL.isExecutableFile else { return false }

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-c", "import imageio_ffmpeg"]
        process.environment = ProcessInfo.processInfo.environment.merging(
            managedEnvironment(fileManager: fileManager),
            uniquingKeysWith: { _, new in new }
        )
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func downloadUVInstaller(fileManager: FileManager) throws -> URL {
        let scriptURL = managedRootURL(fileManager: fileManager).appendingPathComponent("uv-install.sh")
        let url = "https://astral.sh/uv/\(uvVersion)/install.sh"
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/curl"),
            arguments: ["-LsSf", url, "-o", scriptURL.path],
            environment: [:],
            workDirectory: managedRootURL(fileManager: fileManager)
        )
        return scriptURL
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        workDirectory: URL
    ) throws {
        let process = Process()
        var processEnvironment = ProcessInfo.processInfo.environment
        environment.forEach { processEnvironment[$0.key] = $0.value }
        let pathDirectories = runtimeExecutableSearchDirectories().map(\.path) + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        processEnvironment["PATH"] = pathDirectories.joined(separator: ":")

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workDirectory
        process.environment = processEnvironment
        let stdoutURL = workDirectory.appendingPathComponent("managed-runtime-stdout.log")
        let stderrURL = workDirectory.appendingPathComponent("managed-runtime-stderr.log")
        _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()
        try? stdoutHandle.close()
        try? stderrHandle.close()

        guard process.terminationStatus == 0 else {
            let stderrText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
            let stdoutText = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
            let diagnostic = [stderrText, stdoutText]
                .joined(separator: "\n")
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .last ?? "No diagnostic output."
            DictatorLog.packaging.error(
                "Managed runtime command failed executable=\(executableURL.lastPathComponent, privacy: .public) status=\(process.terminationStatus, privacy: .public) diagnostic=\(diagnostic, privacy: .public)"
            )
            throw ManagedGigaAMRuntimeInstallerError.commandFailed(String(diagnostic.prefix(180)))
        }
    }

    private static func ensureDirectories(fileManager: FileManager) throws {
        for url in [
            managedRootURL(fileManager: fileManager),
            uvBinURL(fileManager: fileManager),
            toolBinURL(fileManager: fileManager),
            toolDirURL(fileManager: fileManager),
            uvCacheURL(fileManager: fileManager),
            pythonDirURL(fileManager: fileManager),
            hfHomeURL(fileManager: fileManager),
            xdgCacheURL(fileManager: fileManager),
            xdgDataURL(fileManager: fileManager)
        ] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private static func managedRootURL(fileManager: FileManager) -> URL {
        if let override = environmentValue("DICTATOR_MANAGED_RUNTIME_ROOT"), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        do {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return applicationSupport.appendingPathComponent("Dictator/ManagedRuntime", isDirectory: true)
        } catch {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Dictator-ManagedRuntime", isDirectory: true)
        }
    }

    private static func uvBinURL(fileManager: FileManager) -> URL {
        managedRootURL(fileManager: fileManager).appendingPathComponent("uv-bin", isDirectory: true)
    }

    private static func toolBinURL(fileManager: FileManager) -> URL {
        managedRootURL(fileManager: fileManager).appendingPathComponent("tool-bin", isDirectory: true)
    }

    private static func toolDirURL(fileManager: FileManager) -> URL {
        managedRootURL(fileManager: fileManager).appendingPathComponent("tools", isDirectory: true)
    }

    private static func gigaAMToolPythonURL(fileManager: FileManager) -> URL {
        toolDirURL(fileManager: fileManager)
            .appendingPathComponent("gigaam-mlx", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }

    private static func ffmpegShimURL(fileManager: FileManager) -> URL {
        toolBinURL(fileManager: fileManager).appendingPathComponent("ffmpeg")
    }

    private static func uvCacheURL(fileManager: FileManager) -> URL {
        managedRootURL(fileManager: fileManager).appendingPathComponent("uv-cache", isDirectory: true)
    }

    private static func pythonDirURL(fileManager: FileManager) -> URL {
        managedRootURL(fileManager: fileManager).appendingPathComponent("python", isDirectory: true)
    }

    private static func hfHomeURL(fileManager: FileManager) -> URL {
        managedRootURL(fileManager: fileManager).appendingPathComponent("hf-home", isDirectory: true)
    }

    private static func xdgCacheURL(fileManager: FileManager) -> URL {
        managedRootURL(fileManager: fileManager).appendingPathComponent("xdg-cache", isDirectory: true)
    }

    private static func xdgDataURL(fileManager: FileManager) -> URL {
        managedRootURL(fileManager: fileManager).appendingPathComponent("xdg-data", isDirectory: true)
    }

    private static func environmentValue(_ name: String) -> String? {
        guard let value = getenv(name) else { return nil }
        return String(cString: value)
    }
}

private extension URL {
    var isExecutableFile: Bool {
        FileManager.default.isExecutableFile(atPath: path)
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
