import Foundation
import XCTest
@testable import DshLauncherCore

final class ChildEnvironmentTests: XCTestCase {

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChildEnvTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeNodeBin() throws -> URL {
        let nodeBin = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChildEnvNode-\(UUID().uuidString)/node/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeBin, withIntermediateDirectories: true)
        return nodeBin
    }

    func testExistingPathIsKeptFirst() throws {
        let home = try makeHome()
        let nodeBin = try makeNodeBin()
        let path = ChildEnvironment.path(
            nodeBinDirectory: nodeBin,
            homeDirectory: home,
            existingPath: "/custom/bin:/usr/bin",
            extraEntries: []
        )
        let components = path.split(separator: ":").map(String.init)
        XCTAssertEqual(components.first, "/custom/bin")
        XCTAssertEqual(components[1], "/usr/bin")
    }

    func testNodeBinIsAlwaysIncluded() throws {
        let home = try makeHome()
        let nodeBin = try makeNodeBin()
        let path = ChildEnvironment.path(
            nodeBinDirectory: nodeBin,
            homeDirectory: home,
            existingPath: nil,
            extraEntries: []
        )
        XCTAssertTrue(path.split(separator: ":").map(String.init).contains(nodeBin.path))
    }

    func testWellKnownDirectoriesOnlyWhenPresent() throws {
        let home = try makeHome()
        let nodeBin = try makeNodeBin()
        let npmGlobal = home.appendingPathComponent(".npm-global/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: npmGlobal, withIntermediateDirectories: true)
        // .cargo/bin deliberately not created.
        let path = ChildEnvironment.path(
            nodeBinDirectory: nodeBin,
            homeDirectory: home,
            existingPath: nil,
            extraEntries: []
        )
        let components = path.split(separator: ":").map(String.init)
        XCTAssertTrue(components.contains(npmGlobal.path))
        XCTAssertFalse(components.contains(home.appendingPathComponent(".cargo/bin").path))
    }

    func testNvmNewestVersionBinIsIncluded() throws {
        let home = try makeHome()
        let nodeBin = try makeNodeBin()
        let old = home.appendingPathComponent(".nvm/versions/node/v18.0.0/bin", isDirectory: true)
        let new = home.appendingPathComponent(".nvm/versions/node/v22.13.0/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        let path = ChildEnvironment.path(
            nodeBinDirectory: nodeBin,
            homeDirectory: home,
            existingPath: nil,
            extraEntries: []
        )
        let components = path.split(separator: ":").map(String.init)
        XCTAssertTrue(components.contains(new.path))
        XCTAssertFalse(components.contains(old.path))
    }

    func testExtraEntriesAreAppended() throws {
        let home = try makeHome()
        let nodeBin = try makeNodeBin()
        let path = ChildEnvironment.path(
            nodeBinDirectory: nodeBin,
            homeDirectory: home,
            existingPath: nil,
            extraEntries: ["/opt/tools/bin", "/another/bin", "  /opt/tools/bin  "]
        )
        let components = path.split(separator: ":").map(String.init)
        XCTAssertTrue(components.contains("/opt/tools/bin"))
        XCTAssertTrue(components.contains("/another/bin"))
        // Deduplicated.
        XCTAssertEqual(components.filter { $0 == "/opt/tools/bin" }.count, 1)
    }

    func testSystemDirectoriesAreAlwaysAppendedLast() throws {
        let home = try makeHome()
        let nodeBin = try makeNodeBin()
        let path = ChildEnvironment.path(
            nodeBinDirectory: nodeBin,
            homeDirectory: home,
            existingPath: nil,
            extraEntries: ["/extra"]
        )
        let components = path.split(separator: ":").map(String.init)
        for directory in ChildEnvironment.systemDirectories {
            XCTAssertTrue(components.contains(directory), "missing \(directory)")
        }
        XCTAssertEqual(Array(components.suffix(ChildEnvironment.systemDirectories.count)),
                       ChildEnvironment.systemDirectories)
    }

    func testPathIsDeduplicated() throws {
        let home = try makeHome()
        let nodeBin = try makeNodeBin()
        let path = ChildEnvironment.path(
            nodeBinDirectory: nodeBin,
            homeDirectory: home,
            existingPath: "/usr/bin:/usr/bin",
            extraEntries: ["/usr/bin"]
        )
        let components = path.split(separator: ":").map(String.init)
        XCTAssertEqual(components.filter { $0 == "/usr/bin" }.count, 1)
    }
}
