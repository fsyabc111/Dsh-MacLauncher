import Foundation
import XCTest
@testable import DshLauncherCore

final class ModelsAndSettingsTests: XCTestCase {
    func testManifestValidationAcceptsMatchingArchitecture() throws {
        let manifest = RuntimeManifest(
            schemaVersion: 1,
            dshVersion: "0.1.0",
            nodeVersion: "24.0.0",
            architecture: RuntimeArchitecture.current,
            archiveURL: URL(string: "https://example.com/runtime.zip")!,
            archiveSize: 42,
            sha256: String(repeating: "a", count: 64)
        )
        XCTAssertNoThrow(try manifest.validate())
    }

    func testManifestRejectsInsecureURL() {
        let manifest = RuntimeManifest(
            schemaVersion: 1,
            dshVersion: "0.1.0",
            nodeVersion: "24.0.0",
            architecture: RuntimeArchitecture.current,
            archiveURL: URL(string: "http://example.com/runtime.zip")!,
            archiveSize: 42,
            sha256: String(repeating: "a", count: 64)
        )
        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(error as? RuntimeError, .insecureDownloadURL)
        }
    }

    @MainActor
    func testRecentWorkspacesAreDeduplicatedAndCapped() {
        let suite = "SettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LauncherSettingsStore(defaults: defaults)

        for index in 0..<10 {
            store.addRecentWorkspace(URL(fileURLWithPath: "/tmp/project-\(index)"))
        }
        store.addRecentWorkspace(URL(fileURLWithPath: "/tmp/project-5"))

        XCTAssertEqual(store.value.recentWorkspaces.count, 8)
        XCTAssertEqual(store.value.recentWorkspaces.first, "/tmp/project-5")
        XCTAssertEqual(store.value.recentWorkspaces.filter { $0 == "/tmp/project-5" }.count, 1)
    }

    @MainActor
    func testPreferredPortIsClamped() {
        let suite = "PortSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LauncherSettingsStore(defaults: defaults)
        store.update { $0.preferredPort = 100_000 }
        XCTAssertEqual(store.value.preferredPort, 65_535)
    }

    @MainActor
    func testWorkspaceFallsBackToProvidedDefault() {
        let suite = "WorkspaceFallbackTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LauncherSettingsStore(defaults: defaults)
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

        XCTAssertEqual(store.resolvedWorkspaceURL(default: home), home)

        let selected = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        store.addRecentWorkspace(selected)
        XCTAssertEqual(store.resolvedWorkspaceURL(default: home), selected)
    }

    func testSettingsDecodeToleratesMissingNewKeys() throws {
        // JSON persisted by an older launcher version: no extraPathEntries.
        let legacyJSON = """
        {"portMode":"fixed","preferredPort":4321,"openBrowserAfterStart":false,
         "launchAtLogin":true,"startServiceAtLogin":true,
         "recentWorkspaces":["/tmp/a"],"didCompleteOnboarding":true}
        """
        let decoded = try JSONDecoder().decode(
            LauncherSettings.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertEqual(decoded.portMode, .fixed)
        XCTAssertEqual(decoded.preferredPort, 4321)
        XCTAssertEqual(decoded.openBrowserAfterStart, false)
        XCTAssertEqual(decoded.launchAtLogin, true)
        XCTAssertEqual(decoded.startServiceAtLogin, true)
        XCTAssertEqual(decoded.recentWorkspaces, ["/tmp/a"])
        XCTAssertEqual(decoded.didCompleteOnboarding, true)
        XCTAssertEqual(decoded.extraPathEntries, [])
    }

    func testSettingsRoundTripPreservesExtraPathEntries() throws {
        var settings = LauncherSettings()
        settings.extraPathEntries = ["/opt/tools/bin", "/srv/bin"]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(LauncherSettings.self, from: data)
        XCTAssertEqual(decoded.extraPathEntries, ["/opt/tools/bin", "/srv/bin"])
    }
}
