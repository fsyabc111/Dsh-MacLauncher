import Darwin
import DshLauncherCore
import Foundation

enum SmokeCheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
struct DshLauncherSmokeChecks {
    @MainActor
    static func main() async throws {
        try checkRedaction()
        try checkManifestValidation()
        try await checkServiceLifecycle()
        print("DSH Launcher smoke checks passed")
    }

    private static func checkRedaction() throws {
        let redacted = SensitiveDataRedactor.redact(
            "api_key=sk-abcdefghijklmnopqrstuvwxyz Authorization: Bearer secret.value"
        )
        guard !redacted.contains("abcdefghijklmnopqrstuvwxyz"),
              !redacted.contains("secret.value") else {
            throw SmokeCheckError.failed("Sensitive log values were not redacted")
        }
    }

    private static func checkManifestValidation() throws {
        let manifest = RuntimeManifest(
            schemaVersion: 1,
            dshVersion: "smoke",
            nodeVersion: "smoke",
            architecture: RuntimeArchitecture.current,
            archiveURL: URL(fileURLWithPath: "/tmp/runtime.zip"),
            archiveSize: 1,
            sha256: String(repeating: "a", count: 64)
        )
        try manifest.validate()
    }

    @MainActor
    private static func checkServiceLifecycle() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "DshLauncherSmokeChecks-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let runtimeRoot = root.appendingPathComponent("runtime", isDirectory: true)
        let node = runtimeRoot.appendingPathComponent("node/bin/node")
        let dsh = runtimeRoot.appendingPathComponent("app/node_modules/@deepseek-ai/dsh/lib/bin.js")
        try fileManager.createDirectory(at: node.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dsh.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        shift
        port="3080"
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--port" ]; then port="$2"; shift 2; else shift; fi
        done
        echo "dsh web: http://127.0.0.1:$port"
        exec /usr/bin/python3 -m http.server "$port" --bind 127.0.0.1
        """
        try script.write(to: node, atomically: true, encoding: .utf8)
        try "// smoke fixture\n".write(to: dsh, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)

        let manifest = RuntimeManifest(
            schemaVersion: 1,
            dshVersion: "smoke",
            nodeVersion: "smoke",
            architecture: RuntimeArchitecture.current,
            archiveURL: URL(fileURLWithPath: "/tmp/runtime.zip"),
            archiveSize: 1,
            sha256: String(repeating: "a", count: 64)
        )
        let runtime = RuntimeInstallation(manifest: manifest, rootURL: runtimeRoot)
        let paths = LauncherPaths(
            applicationSupportURL: root.appendingPathComponent("Application Support"),
            logsURL: root.appendingPathComponent("Logs"),
            dshHomeURL: root.appendingPathComponent(".dsh")
        )
        let logs = LogStore(directoryURL: paths.logsURL)
        let controller = ServiceController(logs: logs, paths: paths)
        let port = try availablePort()

        try await controller.start(
            runtime: runtime,
            workspace: root,
            portMode: .fixed,
            preferredPort: port
        )
        guard controller.state.phase == .running,
              controller.state.url?.port == port,
              let pid = controller.state.pid else {
            throw SmokeCheckError.failed("Service did not reach the running state")
        }

        await controller.stop()
        guard controller.state.phase == .stopped, kill(pid, 0) != 0 else {
            throw SmokeCheckError.failed("Service process remained after stop")
        }
    }

    private static func availablePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SmokeCheckError.failed("Could not create a socket") }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw SmokeCheckError.failed("Could not reserve a port") }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(descriptor, $0, &length)
            }
        }
        return Int(UInt16(bigEndian: bound.sin_port))
    }
}

