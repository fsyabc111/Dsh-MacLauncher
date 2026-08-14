import Foundation
import XCTest
@testable import DshLauncherCore

final class DiagnosticsTests: XCTestCase {
    func testExportContainsOnlySnapshotAndRedactedLogs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let log = root.appendingPathComponent("source.log")
        try "api_key=sk-abcdefghijklmnopqrstuvwxyz".write(to: log, atomically: true, encoding: .utf8)
        let destination = root.appendingPathComponent("diagnostics.zip")
        let snapshot = DiagnosticsSnapshot(
            applicationVersion: "1.0",
            nodeVersion: "24",
            dshVersion: "0.1",
            architecture: RuntimeArchitecture.current,
            workspacePath: "/tmp/project",
            servicePhase: .stopped,
            serviceURL: nil,
            dshHomePath: "/Users/test/.dsh",
            webProfileExists: true
        )

        try await DiagnosticsService.export(
            snapshot: snapshot,
            logURLs: [log],
            destinationURL: destination
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", destination.path, extracted.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let files = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), ["diagnostics.json", "launcher-0.log"])
        let exportedLog = try String(contentsOf: extracted.appendingPathComponent("launcher-0.log"))
        XCTAssertFalse(exportedLog.contains("abcdefghijklmnopqrstuvwxyz"))
    }
}
