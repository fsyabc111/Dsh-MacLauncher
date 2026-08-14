import Combine
import CryptoKit
import Foundation

public struct LauncherPaths: Sendable {
    public let applicationSupportURL: URL
    public let logsURL: URL
    public let dshHomeURL: URL

    public init(
        applicationSupportURL: URL,
        logsURL: URL,
        dshHomeURL: URL
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.logsURL = logsURL
        self.dshHomeURL = dshHomeURL
    }

    public static func live(fileManager: FileManager = .default) -> LauncherPaths {
        let home = fileManager.homeDirectoryForCurrentUser
        return LauncherPaths(
            applicationSupportURL: home.appendingPathComponent(
                "Library/Application Support/DSH Launcher",
                isDirectory: true
            ),
            logsURL: home.appendingPathComponent("Library/Logs/DSH Launcher", isDirectory: true),
            dshHomeURL: home.appendingPathComponent(".dsh", isDirectory: true)
        )
    }

    public var runtimesURL: URL {
        applicationSupportURL.appendingPathComponent("Runtimes", isDirectory: true)
    }

    public var processOwnershipURL: URL {
        applicationSupportURL.appendingPathComponent("owned-process.json")
    }
}

@MainActor
public final class RuntimeManager: ObservableObject {
    nonisolated public static let defaultManifestURL = URL(
        string: "https://github.com/fsyabc111/Dsh-MacLauncher/releases/latest/download/runtime-manifest.json"
    )!

    @Published public private(set) var phase: RuntimeInstallPhase = .checking
    @Published public private(set) var availableManifest: RuntimeManifest?

    public private(set) var activeInstallation: RuntimeInstallation?

    public var hasPendingRollback: Bool {
        defaults.string(forKey: pendingPreviousVersionKey) != nil
    }

    private let manifestURL: URL
    private let paths: LauncherPaths
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let activeVersionKey = "activeRuntimeVersion"
    private let pendingPreviousVersionKey = "pendingPreviousRuntimeVersion"

    public init(
        manifestURL: URL = RuntimeManager.defaultManifestURL,
        paths: LauncherPaths = .live(),
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        self.manifestURL = manifestURL
        self.paths = paths
        self.fileManager = fileManager
        self.defaults = defaults
    }

    public func refreshInstalledState() {
        do {
            try fileManager.createDirectory(at: paths.runtimesURL, withIntermediateDirectories: true)
            if let version = defaults.string(forKey: activeVersionKey),
               let installation = try loadInstallation(version: version) {
                activeInstallation = installation
                phase = .ready(installation)
                return
            }

            let versions = try fileManager.contentsOfDirectory(
                at: paths.runtimesURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ).sorted { lhs, rhs in
                let leftDate = try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let rightDate = try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (leftDate ?? .distantPast) > (rightDate ?? .distantPast)
            }

            for candidate in versions {
                if let installation = try loadInstallation(version: candidate.lastPathComponent) {
                    defaults.set(installation.manifest.dshVersion, forKey: activeVersionKey)
                    activeInstallation = installation
                    phase = .ready(installation)
                    return
                }
            }
            activeInstallation = nil
            phase = .missing
        } catch {
            activeInstallation = nil
            phase = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    public func checkForUpdates() async throws -> RuntimeManifest {
        let data: Data
        if manifestURL.isFileURL {
            data = try Data(contentsOf: manifestURL)
        } else {
            let (downloadedData, response) = try await URLSession.shared.data(from: manifestURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            data = downloadedData
        }
        let manifest = try JSONDecoder().decode(RuntimeManifest.self, from: data)
        try manifest.validate()
        if manifest.dshVersion != activeInstallation?.manifest.dshVersion {
            availableManifest = manifest
        } else {
            availableManifest = nil
        }
        return manifest
    }

    public func install(_ manifest: RuntimeManifest) async throws {
        try manifest.validate()
        phase = .downloading
        try fileManager.createDirectory(at: paths.runtimesURL, withIntermediateDirectories: true)

        let transactionURL = paths.applicationSupportURL.appendingPathComponent(
            "Install-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: transactionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transactionURL) }

        let archiveURL = transactionURL.appendingPathComponent("runtime.zip")
        if manifest.archiveURL.isFileURL {
            try fileManager.copyItem(at: manifest.archiveURL, to: archiveURL)
        } else {
            let (temporaryURL, response) = try await URLSession.shared.download(from: manifest.archiveURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            try fileManager.moveItem(at: temporaryURL, to: archiveURL)
        }

        let fileSize = ((try fileManager.attributesOfItem(atPath: archiveURL.path)[.size]) as? NSNumber)?.int64Value
        guard fileSize == manifest.archiveSize else {
            throw RuntimeError.invalidManifest("archiveSize")
        }

        phase = .verifying
        let digest = try Self.sha256(of: archiveURL)
        guard digest.caseInsensitiveCompare(manifest.sha256) == .orderedSame else {
            throw RuntimeError.checksumMismatch
        }

        phase = .installing
        let extractionURL = transactionURL.appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        try await Self.runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archiveURL.path, extractionURL.path]
        )

        let extractedRuntimeURL = extractionURL.appendingPathComponent("runtime", isDirectory: true)
        let candidate = RuntimeInstallation(manifest: manifest, rootURL: extractedRuntimeURL)
        guard fileManager.isExecutableFile(atPath: candidate.nodeExecutable.path),
              fileManager.fileExists(atPath: candidate.dshEntryPoint.path) else {
            throw RuntimeError.malformedArchive
        }

        let versionOutput = try await Self.runProcess(
            executable: candidate.nodeExecutable,
            arguments: [candidate.dshEntryPoint.path, "--version"]
        )
        guard versionOutput.contains(manifest.dshVersion) else {
            throw RuntimeError.selfCheckFailed(versionOutput)
        }

        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(
            to: extractedRuntimeURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        let destinationURL = paths.runtimesURL.appendingPathComponent(
            manifest.dshVersion,
            isDirectory: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: extractedRuntimeURL, to: destinationURL)

        if let previous = activeInstallation?.manifest.dshVersion,
           previous != manifest.dshVersion {
            defaults.set(previous, forKey: pendingPreviousVersionKey)
        }
        defaults.set(manifest.dshVersion, forKey: activeVersionKey)
        let installed = RuntimeInstallation(manifest: manifest, rootURL: destinationURL)
        activeInstallation = installed
        availableManifest = nil
        phase = .ready(installed)
    }

    public func confirmActiveRuntime() {
        defaults.removeObject(forKey: pendingPreviousVersionKey)
    }

    @discardableResult
    public func rollbackIfPending() throws -> RuntimeInstallation {
        guard let previous = defaults.string(forKey: pendingPreviousVersionKey),
              let installation = try loadInstallation(version: previous) else {
            throw RuntimeError.noPreviousVersion
        }
        defaults.set(previous, forKey: activeVersionKey)
        defaults.removeObject(forKey: pendingPreviousVersionKey)
        activeInstallation = installation
        phase = .ready(installation)
        return installation
    }

    private func loadInstallation(version: String) throws -> RuntimeInstallation? {
        let root = paths.runtimesURL.appendingPathComponent(version, isDirectory: true)
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(RuntimeManifest.self, from: data) else {
            return nil
        }
        try manifest.validate()
        let installation = RuntimeInstallation(manifest: manifest, rootURL: root)
        guard fileManager.isExecutableFile(atPath: installation.nodeExecutable.path),
              fileManager.fileExists(atPath: installation.dshEntryPoint.path) else {
            return nil
        }
        return installation
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    nonisolated private static func runProcess(
        executable: URL,
        arguments: [String]
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { completed in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                if completed.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: RuntimeError.selfCheckFailed(output))
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
