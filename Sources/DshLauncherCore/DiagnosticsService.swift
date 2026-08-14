import Foundation

public struct DiagnosticsSnapshot: Codable, Sendable {
    public let generatedAt: Date
    public let applicationVersion: String
    public let nodeVersion: String?
    public let dshVersion: String?
    public let architecture: String
    public let workspacePath: String?
    public let servicePhase: ServicePhase
    public let serviceURL: String?
    public let dshHomePath: String
    public let webProfileExists: Bool

    public init(
        generatedAt: Date = Date(),
        applicationVersion: String,
        nodeVersion: String?,
        dshVersion: String?,
        architecture: String,
        workspacePath: String?,
        servicePhase: ServicePhase,
        serviceURL: String?,
        dshHomePath: String,
        webProfileExists: Bool
    ) {
        self.generatedAt = generatedAt
        self.applicationVersion = applicationVersion
        self.nodeVersion = nodeVersion
        self.dshVersion = dshVersion
        self.architecture = architecture
        self.workspacePath = workspacePath
        self.servicePhase = servicePhase
        self.serviceURL = serviceURL
        self.dshHomePath = dshHomePath
        self.webProfileExists = webProfileExists
    }
}

public enum DiagnosticsService {
    public static func export(
        snapshot: DiagnosticsSnapshot,
        logURLs: [URL],
        destinationURL: URL
    ) async throws {
        let fileManager = FileManager.default
        let stagingURL = fileManager.temporaryDirectory.appendingPathComponent(
            "DSH-Launcher-Diagnostics-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: stagingURL.appendingPathComponent("diagnostics.json"), options: .atomic)

        for (index, logURL) in logURLs.enumerated() {
            guard let contents = try? String(contentsOf: logURL, encoding: .utf8) else { continue }
            let redacted = SensitiveDataRedactor.redact(contents)
            try redacted.write(
                to: stagingURL.appendingPathComponent("launcher-\(index).log"),
                atomically: true,
                encoding: .utf8
            )
        }

        try await runDitto(source: stagingURL, destination: destinationURL)
    }

    private static func runDitto(source: URL, destination: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", source.path, destination.path]
            process.standardOutput = FileHandle.nullDevice
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.terminationHandler = { completed in
                if completed.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(
                        throwing: LauncherError.launchFailed(String(decoding: data, as: UTF8.self))
                    )
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
