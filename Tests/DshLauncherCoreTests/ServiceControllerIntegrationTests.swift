import Darwin
import Foundation
import XCTest
@testable import DshLauncherCore

final class ServiceControllerIntegrationTests: XCTestCase {
    @MainActor
    func testStartsHealthyServiceAndStopsWithoutOrphan() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServiceControllerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let runtime = try makeFakeRuntime(root: root)
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
        XCTAssertEqual(controller.state.phase, .running)
        XCTAssertEqual(controller.state.url?.port, port)
        let pid = try XCTUnwrap(controller.state.pid)

        await controller.stop()

        XCTAssertEqual(controller.state.phase, .stopped)
        XCTAssertNotEqual(kill(pid, 0), 0)
    }

    private func makeFakeRuntime(root: URL) throws -> RuntimeInstallation {
        let runtimeRoot = root.appendingPathComponent("runtime", isDirectory: true)
        let node = runtimeRoot.appendingPathComponent("node/bin/node")
        let dsh = runtimeRoot.appendingPathComponent("app/node_modules/@deepseek-ai/dsh/lib/bin.js")
        try FileManager.default.createDirectory(at: node.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dsh.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = #"""
        #!/bin/sh
        shift
        port="3080"
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--port" ]; then port="$2"; shift 2; else shift; fi
        done
        echo "dsh web: http://127.0.0.1:$port"
        exec /usr/bin/python3 -m http.server "$port" --bind 127.0.0.1
        """#
        try script.write(to: node, atomically: true, encoding: .utf8)
        try "// fixture\n".write(to: dsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let manifest = RuntimeManifest(
            schemaVersion: 1,
            dshVersion: "test",
            nodeVersion: "test",
            architecture: RuntimeArchitecture.current,
            archiveURL: URL(fileURLWithPath: "/tmp/test.zip"),
            archiveSize: 1,
            sha256: String(repeating: "a", count: 64)
        )
        return RuntimeInstallation(manifest: manifest, rootURL: runtimeRoot)
    }

    private func availablePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }
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
