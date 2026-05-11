import Foundation

enum GigaAMRuntimeError: Error, LocalizedError {
    case runtimeUnavailable
    case commandFailed(String, String)
    case transcriptEmpty

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            """
            GigaAM runtime is not installed. Install gigaam-mlx, gigastt, or Python package gigaam.
            """
        case let .commandFailed(runtime, reason):
            "GigaAM failed via \(runtime): \(reason)"
        case .transcriptEmpty:
            "GigaAM returned empty text. Check microphone input."
        }
    }
}

enum GigaAMRuntime {
    static let modelName = "GigaAM v3 e2e RNNT"

    static func hasQuickRuntimeCandidate() -> Bool {
        executablePath(named: "gigaam-mlx") != nil ||
            executablePath(named: "gigastt") != nil ||
            executablePath(named: "python3") != nil
    }

    static func prewarm() async throws {
        try await Task.detached(priority: .userInitiated) {
            let backend = try findBackend()
            DictatorLog.transcription.info("GigaAM prewarm started backend=\(backend.name, privacy: .public)")
            let workDirectory = try makeWorkDirectory(prefix: "Dictator-GigaAM-Warmup")
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            switch backend {
            case let .gigaamMLX(path):
                let audioURL = workDirectory.appendingPathComponent("warmup.wav")
                try WAVFileWriter.writeSilentWAV(to: audioURL)
                _ = try runProcess(
                    executablePath: path,
                    arguments: [audioURL.path, "--model-type", "rnnt", "--format", "txt", "--quiet"],
                    runtimeName: backend.name,
                    workDirectory: workDirectory
                )
            case let .gigastt(path):
                _ = try runProcess(
                    executablePath: path,
                    arguments: ["download"],
                    runtimeName: backend.name,
                    workDirectory: workDirectory
                )
            case let .pythonGigaAM(path):
                let scriptURL = try writePythonScript(
                    to: workDirectory,
                    body: """
                    import sys
                    import gigaam

                    gigaam.load_model("v3_e2e_rnnt")
                    print("ready")
                    """
                )
                _ = try runProcess(
                    executablePath: path,
                    arguments: [scriptURL.path],
                    runtimeName: backend.name,
                    workDirectory: workDirectory
                )
            }
            DictatorLog.transcription.info("GigaAM prewarm finished backend=\(backend.name, privacy: .public)")
        }.value
    }

    static func transcribe(_ recording: AudioRecording) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let backend = try findBackend()
            DictatorLog.transcription.info(
                "GigaAM transcription started backend=\(backend.name, privacy: .public) duration=\(recording.duration, privacy: .public)"
            )
            let workDirectory = try makeWorkDirectory(prefix: "Dictator-GigaAM")
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            let audioURL = workDirectory.appendingPathComponent("dictation.wav")
            try WAVFileWriter.write(recording, to: audioURL)

            let output: String
            switch backend {
            case let .gigaamMLX(path):
                let stdout = try runProcess(
                    executablePath: path,
                    arguments: [
                        audioURL.path,
                        "--model-type", "rnnt",
                        "--format", "txt",
                        "--quiet",
                        "--output-dir", workDirectory.path
                    ],
                    runtimeName: backend.name,
                    workDirectory: workDirectory
                )
                output = transcriptText(in: workDirectory) ?? stdout
            case let .gigastt(path):
                output = try runProcess(
                    executablePath: path,
                    arguments: ["transcribe", audioURL.path],
                    runtimeName: backend.name,
                    workDirectory: workDirectory
                )
            case let .pythonGigaAM(path):
                let scriptURL = try writePythonScript(
                    to: workDirectory,
                    body: """
                    import sys
                    import gigaam

                    model = gigaam.load_model("v3_e2e_rnnt")
                    text = model.transcribe(sys.argv[1])
                    print(text if text is not None else "")
                    """
                )
                output = try runProcess(
                    executablePath: path,
                    arguments: [scriptURL.path, audioURL.path],
                    runtimeName: backend.name,
                    workDirectory: workDirectory
                )
            }

            guard let transcript = extractTranscript(from: output) else {
                DictatorLog.transcription.error("GigaAM transcription returned empty text")
                throw GigaAMRuntimeError.transcriptEmpty
            }
            DictatorLog.transcription.info(
                "GigaAM transcription finished backend=\(backend.name, privacy: .public) textLength=\((transcript as NSString).length, privacy: .public)"
            )
            return transcript
        }.value
    }

    private enum Backend {
        case gigaamMLX(String)
        case gigastt(String)
        case pythonGigaAM(String)

        var name: String {
            switch self {
            case .gigaamMLX: "gigaam-mlx"
            case .gigastt: "gigastt"
            case .pythonGigaAM: "python-gigaam"
            }
        }
    }

    private static func findBackend() throws -> Backend {
        if let path = executablePath(named: "gigaam-mlx") {
            return .gigaamMLX(path)
        }

        if let path = executablePath(named: "gigastt") {
            return .gigastt(path)
        }

        if let pythonPath = pythonWithGigaAMModule() {
            return .pythonGigaAM(pythonPath)
        }

        DictatorLog.transcription.error("GigaAM runtime unavailable")
        throw GigaAMRuntimeError.runtimeUnavailable
    }

    private static func pythonWithGigaAMModule() -> String? {
        executableSearchDirectories()
            .map { $0.appendingPathComponent("python3").path }
            .first { path in
                guard FileManager.default.isExecutableFile(atPath: path) else { return false }
                return processExitsSuccessfully(
                    executablePath: path,
                    arguments: [
                        "-c",
                        "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('gigaam') else 1)"
                    ]
                )
            }
    }

    private static func executablePath(named executableName: String) -> String? {
        executableSearchDirectories()
            .map { $0.appendingPathComponent(executableName).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func executableSearchDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            home.appendingPathComponent(".local/bin", isDirectory: true),
            home.appendingPathComponent("Library/Python/3.14/bin", isDirectory: true),
            home.appendingPathComponent("Library/Python/3.13/bin", isDirectory: true),
            home.appendingPathComponent("Library/Python/3.12/bin", isDirectory: true),
            home.appendingPathComponent("Library/Python/3.11/bin", isDirectory: true),
            home.appendingPathComponent("Library/Python/3.10/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true)
        ]
    }

    private static func processExitsSuccessfully(executablePath: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
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

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        runtimeName: String,
        workDirectory: URL
    ) throws -> String {
        let process = Process()
        let stdoutURL = workDirectory.appendingPathComponent("stdout.log")
        let stderrURL = workDirectory.appendingPathComponent("stderr.log")
        _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = workDirectory
        process.environment = processEnvironment()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()
        try? stdout.close()
        try? stderr.close()

        let stdoutText = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderrText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        guard process.terminationStatus == 0 else {
            let diagnostic = diagnosticMessage(stdout: stdoutText, stderr: stderrText)
            DictatorLog.transcription.error(
                "GigaAM command failed runtime=\(runtimeName, privacy: .public) status=\(process.terminationStatus, privacy: .public) diagnostic=\(diagnostic, privacy: .public)"
            )
            throw GigaAMRuntimeError.commandFailed(runtimeName, diagnostic)
        }

        return stdoutText
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let knownDirectories = executableSearchDirectories().map(\.path)
        let inheritedDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let path = (knownDirectories + inheritedDirectories)
            .reduce(into: [String]()) { result, directory in
                guard !directory.isEmpty, !result.contains(directory) else { return }
                result.append(directory)
            }
            .joined(separator: ":")

        environment["PATH"] = path
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        return environment
    }

    private static func diagnosticMessage(stdout: String, stderr: String) -> String {
        let message = [stderr, stdout]
            .joined(separator: "\n")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.contains("Fetching ") && !$0.contains("it/s") }
            .filter { !$0.hasPrefix("Saved:") }
            .last

        return String((message ?? "No diagnostic output.").prefix(180))
    }

    private static func extractTranscript(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let text = jsonTranscript(from: trimmed), !text.isEmpty {
            return text
        }

        return trimmed
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { line in
                !line.isEmpty &&
                    !line.localizedCaseInsensitiveContains("download") &&
                    !line.localizedCaseInsensitiveContains("model") &&
                    !line.localizedCaseInsensitiveContains("loading")
            }
    }

    private static func transcriptText(in directory: URL) -> String? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return files
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                try? String(contentsOf: url, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { !$0.isEmpty }
    }

    private static func jsonTranscript(from output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let text = dictionary["text"] as? String else {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeWorkDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writePythonScript(to directory: URL, body: String) throws -> URL {
        let scriptURL = directory.appendingPathComponent("run_gigaam.py")
        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }
}

private enum WAVFileWriter {
    private static let targetSampleRate: Double = 16_000

    static func write(_ recording: AudioRecording, to url: URL) throws {
        let samples = resampleIfNeeded(recording.samples, from: recording.sampleRate)
        try writePCM(samples: samples, sampleRate: UInt32(targetSampleRate), to: url)
    }

    static func writeSilentWAV(to url: URL) throws {
        try writePCM(samples: Array(repeating: 0, count: 1_600), sampleRate: UInt32(targetSampleRate), to: url)
    }

    private static func resampleIfNeeded(_ samples: [Float], from sourceSampleRate: Double) -> [Float] {
        guard !samples.isEmpty,
              sourceSampleRate > 0,
              abs(sourceSampleRate - targetSampleRate) > 0.5 else {
            return samples
        }

        let outputCount = max(1, Int(Double(samples.count) * targetSampleRate / sourceSampleRate))
        let step = sourceSampleRate / targetSampleRate

        return (0..<outputCount).map { index in
            let sourcePosition = Double(index) * step
            let lowerIndex = min(Int(sourcePosition), samples.count - 1)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            return samples[lowerIndex] * (1 - fraction) + samples[upperIndex] * fraction
        }
    }

    private static func writePCM(samples: [Float], sampleRate: UInt32, to url: URL) throws {
        var data = Data()
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let pcmDataSize = UInt32(samples.count * 2)

        data.append("RIFF".data(using: .ascii)!)
        data.appendLittleEndian(UInt32(36) + pcmDataSize)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channels)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append("data".data(using: .ascii)!)
        data.appendLittleEndian(pcmDataSize)

        for sample in samples {
            let clipped = max(-1, min(1, sample))
            data.appendLittleEndian(Int16(clipped * Float(Int16.max)))
        }

        try data.write(to: url, options: [.atomic])
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(contentsOf: buffer)
        }
    }
}
