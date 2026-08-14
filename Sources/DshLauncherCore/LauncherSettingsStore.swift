import Combine
import Foundation

public struct LauncherSettings: Codable, Equatable, Sendable {
    public var portMode: PortMode = .automatic
    public var preferredPort: Int = 3080
    public var openBrowserAfterStart = true
    public var launchAtLogin = false
    public var startServiceAtLogin = false
    public var recentWorkspaces: [String] = []
    public var didCompleteOnboarding = false

    public init() {}
}

@MainActor
public final class LauncherSettingsStore: ObservableObject {
    @Published public private(set) var value: LauncherSettings

    private let defaults: UserDefaults
    private let storageKey: String

    public init(defaults: UserDefaults = .standard, storageKey: String = "launcherSettings") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(LauncherSettings.self, from: data) {
            value = decoded
        } else {
            value = LauncherSettings()
        }
    }

    public func update(_ mutate: (inout LauncherSettings) -> Void) {
        var updated = value
        mutate(&updated)
        updated.preferredPort = min(max(updated.preferredPort, 1), 65_535)
        value = updated
        persist()
    }

    public func addRecentWorkspace(_ url: URL) {
        let path = url.standardizedFileURL.path
        update { settings in
            settings.recentWorkspaces.removeAll { $0 == path }
            settings.recentWorkspaces.insert(path, at: 0)
            settings.recentWorkspaces = Array(settings.recentWorkspaces.prefix(8))
        }
    }

    public func removeRecentWorkspace(_ path: String) {
        update { $0.recentWorkspaces.removeAll { $0 == path } }
    }

    public var selectedWorkspaceURL: URL? {
        value.recentWorkspaces.first.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

