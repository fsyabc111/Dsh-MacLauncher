import Foundation
import XCTest
@testable import DshLauncherCore

final class LogStoreTests: XCTestCase {
    func testRedactorRemovesCommonSecrets() {
        let input = "api_key=sk-abcdefghijklmnopqrstuvwxyz Authorization: Bearer abc.def token=secret123"
        let output = SensitiveDataRedactor.redact(input)
        XCTAssertFalse(output.contains("abcdefghijklmnopqrstuvwxyz"))
        XCTAssertFalse(output.contains("abc.def"))
        XCTAssertFalse(output.contains("secret123"))
        XCTAssertTrue(output.contains("<redacted>"))
    }

    @MainActor
    func testLogRotationRetainsConfiguredFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LogStore(directoryURL: directory, maxFileSize: 20, retainedFileCount: 3)

        store.append("first-entry-123456789\n")
        store.append("second-entry-123456789\n")
        store.append("third-entry-123456789\n")

        XCTAssertLessThanOrEqual(store.logFileURLs().count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.currentLogURL.path))
    }
}

