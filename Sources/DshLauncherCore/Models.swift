import Foundation

public enum PortMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case fixed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .fixed: "Fixed"
        }
    }
}

public enum ServicePhase: String, Codable, Sendable {
    case runtimeMissing
    case installing
    case stopped
    case starting
    case running
    case stopping
    case failed
}

public struct ServiceState: Equatable, Sendable {
    public var phase: ServicePhase
    public var url: URL?
    public var pid: Int32?
    public var message: String?

    public init(
        phase: ServicePhase,
        url: URL? = nil,
        pid: Int32? = nil,
        message: String? = nil
    ) {
        self.phase = phase
        self.url = url
        self.pid = pid
        self.message = message
    }
}

public struct RuntimeManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let dshVersion: String
    public let nodeVersion: String
    public let architecture: String
    public let archiveURL: URL
    public let archiveSize: Int64
    public let sha256: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case dshVersion
        case nodeVersion
        case architecture
        case archiveURL = "archiveUrl"
        case archiveSize
        case sha256
    }

    public init(
        schemaVersion: Int,
        dshVersion: String,
        nodeVersion: String,
        architecture: String,
        archiveURL: URL,
        archiveSize: Int64,
        sha256: String
    ) {
        self.schemaVersion = schemaVersion
        self.dshVersion = dshVersion
        self.nodeVersion = nodeVersion
        self.architecture = architecture
        self.archiveURL = archiveURL
        self.archiveSize = archiveSize
        self.sha256 = sha256
    }

    public func validate(expectedArchitecture: String = RuntimeArchitecture.current) throws {
        guard schemaVersion == 1 else { throw RuntimeError.unsupportedManifest }
        guard architecture == expectedArchitecture else {
            throw RuntimeError.unsupportedArchitecture(architecture)
        }
        guard archiveURL.scheme == "https" || archiveURL.isFileURL else {
            throw RuntimeError.insecureDownloadURL
        }
        guard archiveSize > 0 else { throw RuntimeError.invalidManifest("archiveSize") }
        guard sha256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else {
            throw RuntimeError.invalidManifest("sha256")
        }
        guard !dshVersion.isEmpty, !nodeVersion.isEmpty else {
            throw RuntimeError.invalidManifest("version")
        }
    }
}

public enum RuntimeArchitecture {
    public static var current: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unsupported"
        #endif
    }
}

public struct RuntimeInstallation: Codable, Equatable, Sendable {
    public let manifest: RuntimeManifest
    public let rootURL: URL

    public init(manifest: RuntimeManifest, rootURL: URL) {
        self.manifest = manifest
        self.rootURL = rootURL
    }

    public var nodeExecutable: URL {
        rootURL.appendingPathComponent("node/bin/node")
    }

    public var dshEntryPoint: URL {
        rootURL.appendingPathComponent("app/node_modules/@deepseek-ai/dsh/lib/bin.js")
    }
}

public enum RuntimeInstallPhase: Equatable, Sendable {
    case checking
    case missing
    case downloading
    case verifying
    case installing
    case ready(RuntimeInstallation)
    case failed(String)
}

public enum RuntimeError: LocalizedError, Equatable {
    case unsupportedManifest
    case unsupportedArchitecture(String)
    case insecureDownloadURL
    case invalidManifest(String)
    case checksumMismatch
    case malformedArchive
    case selfCheckFailed(String)
    case noPreviousVersion

    public var errorDescription: String? {
        switch self {
        case .unsupportedManifest: "Unsupported runtime manifest version."
        case let .unsupportedArchitecture(value): "Runtime architecture \(value) is not supported on this Mac."
        case .insecureDownloadURL: "Runtime downloads must use HTTPS."
        case let .invalidManifest(field): "The runtime manifest contains an invalid \(field)."
        case .checksumMismatch: "The downloaded runtime failed its integrity check."
        case .malformedArchive: "The runtime archive has an unexpected layout."
        case let .selfCheckFailed(output): "The runtime self-check failed: \(output)"
        case .noPreviousVersion: "There is no previous runtime to restore."
        }
    }
}

public enum LauncherError: LocalizedError, Equatable {
    case runtimeUnavailable
    case invalidWorkspace
    case portUnavailable(Int)
    case launchFailed(String)
    case startupTimedOut
    case serviceExited(String)

    public var errorDescription: String? {
        switch self {
        case .runtimeUnavailable: "Install the DSH runtime before starting the service."
        case .invalidWorkspace: "Choose an existing workspace directory."
        case let .portUnavailable(port): "Port \(port) is already in use."
        case let .launchFailed(reason): "DSH could not start: \(reason)"
        case .startupTimedOut: "DSH did not become ready within 30 seconds."
        case let .serviceExited(reason): "DSH exited unexpectedly: \(reason)"
        }
    }
}

