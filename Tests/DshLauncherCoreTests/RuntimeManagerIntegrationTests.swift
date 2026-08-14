import CryptoKit
import Foundation
import XCTest
@testable import DshLauncherCore

final class RuntimeManagerIntegrationTests: XCTestCase {
    @MainActor
    func testInstallsAndActivatesValidatedRuntimeArchive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeManagerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let archive = try makeFakeRuntimeArchive(root: root, version: "0.1.0-test")
        let data = try Data(contentsOf: archive)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let manifest = RuntimeManifest(
            schemaVersion: 1,
            dshVersion: "0.1.0-test",
            nodeVersion: "24-test",
            architecture: RuntimeArchitecture.current,
            archiveURL: archive,
            archiveSize: Int64(data.count),
            sha256: digest
        )
        let paths = LauncherPaths(
            applicationSupportURL: root.appendingPathComponent("Application Support"),
            logsURL: root.appendingPathComponent("Logs"),
            dshHomeURL: root.appendingPathComponent(".dsh")
        )
        let suite = "RuntimeManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = RuntimeManager(
            manifestURL: archive,
            paths: paths,
            defaults: defaults
        )

        try await manager.install(manifest)

        XCTAssertEqual(manager.activeInstallation?.manifest.dshVersion, "0.1.0-test")
        XCTAssertTrue(FileManager.default.isExecutableFile(
            atPath: manager.activeInstallation!.nodeExecutable.path
        ))
    }

    private func makeFakeRuntimeArchive(root: URL, version: String) throws -> URL {
        let source = root.appendingPathComponent("source/runtime", isDirectory: true)
        let node = source.appendingPathComponent("node/bin/node")
        let dsh = source.appendingPathComponent("app/node_modules/@deepseek-ai/dsh/lib/bin.js")
        try FileManager.default.createDirectory(at: node.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dsh.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\necho '\(version)'\n".write(to: node, atomically: true, encoding: .utf8)
        try "// fixture\n".write(to: dsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)

        let archive = root.appendingPathComponent("runtime.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", source.path, archive.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archive
    }
}
