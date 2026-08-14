import AppKit
import Combine
import DshLauncherCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let paths: LauncherPaths
    let settings: LauncherSettingsStore
    let logs: LogStore
    let runtime: RuntimeManager
    let service: ServiceController

    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var needsOnboarding = false
    @Published var updateMessage: String?

    private var didBootstrap = false

    private init() {
        let paths = LauncherPaths.live()
        let settings = LauncherSettingsStore()
        let logs = LogStore(directoryURL: paths.logsURL)
        let configuredManifestURL = Bundle.main.object(
            forInfoDictionaryKey: "RuntimeManifestURL"
        ) as? String
        let manifestURL = ProcessInfo.processInfo.environment["DSH_RUNTIME_MANIFEST_URL"]
            .flatMap(URL.init(string:))
            ?? configuredManifestURL.flatMap(URL.init(string:))
            ?? RuntimeManager.defaultManifestURL

        self.paths = paths
        self.settings = settings
        self.logs = logs
        runtime = RuntimeManager(manifestURL: manifestURL, paths: paths)
        service = ServiceController(logs: logs, paths: paths)
    }

    var selectedWorkspace: URL? {
        settings.selectedWorkspaceURL
    }

    var workspace: URL {
        settings.resolvedWorkspaceURL(default: FileManager.default.homeDirectoryForCurrentUser)
    }

    var isRuntimeReady: Bool {
        runtime.activeInstallation != nil
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        runtime.refreshInstalledState()
        await service.reconcileOwnedProcess()
        needsOnboarding = !settings.value.didCompleteOnboarding || runtime.activeInstallation == nil
        if needsOnboarding {
            AppWindows.shared.showOnboarding(model: self)
        } else if settings.value.startServiceAtLogin {
            await startService()
        }
        Task { await checkForUpdates(silent: true) }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "选择 DSH 工作区"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = workspace
        if panel.runModal() == .OK, let url = panel.url {
            settings.addRecentWorkspace(url)
        }
    }

    func selectWorkspace(path: String) {
        settings.addRecentWorkspace(URL(fileURLWithPath: path, isDirectory: true))
    }

    func installRuntime() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let manifest = try await runtime.checkForUpdates()
            try await runtime.install(manifest)
        } catch {
            runtime.refreshInstalledState()
            errorMessage = error.localizedDescription
        }
    }

    func startService() async {
        guard !isBusy else { return }
        guard let installation = runtime.activeInstallation else {
            needsOnboarding = true
            AppWindows.shared.showOnboarding(model: self)
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await service.start(
                runtime: installation,
                workspace: workspace,
                portMode: settings.value.portMode,
                preferredPort: settings.value.preferredPort,
                extraPathEntries: settings.value.extraPathEntries
            )
            runtime.confirmActiveRuntime()
            if settings.value.openBrowserAfterStart, let url = service.state.url {
                NSWorkspace.shared.open(url)
            }
        } catch {
            if runtime.hasPendingRollback {
                do {
                    _ = try runtime.rollbackIfPending()
                    errorMessage = "新运行时启动失败，已恢复上一版本。\n\(error.localizedDescription)"
                } catch {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopService() async {
        guard !isBusy else { return }
        isBusy = true
        await service.stop()
        isBusy = false
    }

    func restartService() async {
        guard !isBusy,
              let installation = runtime.activeInstallation else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await service.restart(
                runtime: installation,
                workspace: workspace,
                portMode: settings.value.portMode,
                preferredPort: settings.value.preferredPort,
                extraPathEntries: settings.value.extraPathEntries
            )
            if settings.value.openBrowserAfterStart, let url = service.state.url {
                NSWorkspace.shared.open(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeOnboardingAndStart() async {
        settings.update { $0.didCompleteOnboarding = true }
        needsOnboarding = false
        await startService()
        if service.state.phase == .running {
            AppWindows.shared.close(key: "onboarding")
        }
    }

    func openService() {
        guard let url = service.state.url else { return }
        NSWorkspace.shared.open(url)
    }

    func copyServiceURL() {
        guard let value = service.state.url?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func checkForUpdates(silent: Bool = false) async {
        do {
            let manifest = try await runtime.checkForUpdates()
            if runtime.availableManifest != nil {
                updateMessage = "DSH \(manifest.dshVersion) 可用"
            } else if !silent {
                updateMessage = "当前已是最新版本"
            }
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    func installAvailableUpdate() async {
        guard let manifest = runtime.availableManifest else { return }
        let wasRunning = service.state.phase == .running
        if wasRunning { await stopService() }
        isBusy = true
        errorMessage = nil
        do {
            try await runtime.install(manifest)
            updateMessage = nil
        } catch {
            runtime.refreshInstalledState()
            errorMessage = error.localizedDescription
        }
        isBusy = false
        if wasRunning { await startService() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.update { $0.launchAtLogin = enabled }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func diagnosticsSnapshot() -> DiagnosticsSnapshot {
        let installation = runtime.activeInstallation
        return DiagnosticsSnapshot(
            applicationVersion: appVersion,
            nodeVersion: installation?.manifest.nodeVersion,
            dshVersion: installation?.manifest.dshVersion,
            architecture: RuntimeArchitecture.current,
            workspacePath: workspace.path,
            servicePhase: service.state.phase,
            serviceURL: service.state.url?.absoluteString,
            dshHomePath: paths.dshHomeURL.path,
            webProfileExists: FileManager.default.fileExists(
                atPath: paths.dshHomeURL.appendingPathComponent("profiles/web/package.json").path
            )
        )
    }
}
