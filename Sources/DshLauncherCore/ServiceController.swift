import Combine
import Darwin
import Foundation

private struct OwnedProcess: Codable {
    let pid: Int32
    let nodePath: String
    let dshPath: String
    let workspacePath: String
    let startedAt: Date
    let ownsProcessGroup: Bool
}

@MainActor
public final class ServiceController: ObservableObject {
    @Published public private(set) var state = ServiceState(phase: .stopped)

    public let logs: LogStore
    private let paths: LauncherPaths
    private let fileManager: FileManager
    private var process: Process?
    private var ownsProcessGroup = false
    private var expectedStop = false
    private var startupTask: Task<Void, Error>?

    public init(
        logs: LogStore,
        paths: LauncherPaths = .live(),
        fileManager: FileManager = .default
    ) {
        self.logs = logs
        self.paths = paths
        self.fileManager = fileManager
    }

    public func reconcileOwnedProcess() async {
        guard let owned = loadOwnedProcess() else { return }
        guard Self.processCommand(pid: owned.pid).contains(owned.nodePath),
              Self.processCommand(pid: owned.pid).contains(owned.dshPath) else {
            clearOwnedProcess()
            return
        }
        logs.append("Stopping an orphaned DSH process from the previous launcher session.\n")
        if owned.ownsProcessGroup {
            kill(-owned.pid, SIGTERM)
        } else {
            kill(owned.pid, SIGTERM)
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if kill(owned.pid, 0) == 0 {
            if owned.ownsProcessGroup {
                kill(-owned.pid, SIGKILL)
            } else {
                kill(owned.pid, SIGKILL)
            }
        }
        clearOwnedProcess()
    }

    public func start(
        runtime: RuntimeInstallation,
        workspace: URL,
        portMode: PortMode,
        preferredPort: Int
    ) async throws {
        guard state.phase != .starting, state.phase != .running else { return }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: workspace.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LauncherError.invalidWorkspace
        }
        guard fileManager.isExecutableFile(atPath: runtime.nodeExecutable.path),
              fileManager.fileExists(atPath: runtime.dshEntryPoint.path) else {
            throw LauncherError.runtimeUnavailable
        }

        let selectedPort = try PortResolver.launchPort(
            mode: portMode,
            preferredPort: preferredPort
        )
        state = ServiceState(phase: .starting)
        expectedStop = false

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = runtime.nodeExecutable
        process.arguments = [
            runtime.dshEntryPoint.path,
            "web",
            "--host", "127.0.0.1",
            "--port", String(selectedPort),
        ]
        process.currentDirectoryURL = workspace
        var environment = ProcessInfo.processInfo.environment
        environment["DSH_HOME"] = paths.dshHomeURL.path
        environment["NO_COLOR"] = "1"
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let output = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.consumeOutput(output) }
        }

        process.terminationHandler = { [weak self] completed in
            Task { @MainActor in self?.processDidTerminate(completed) }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            state = ServiceState(phase: .failed, message: error.localizedDescription)
            throw LauncherError.launchFailed(error.localizedDescription)
        }

        self.process = process
        let pid = process.processIdentifier
        ownsProcessGroup = setpgid(pid, pid) == 0
        persistOwnedProcess(
            OwnedProcess(
                pid: pid,
                nodePath: runtime.nodeExecutable.path,
                dshPath: runtime.dshEntryPoint.path,
                workspacePath: workspace.path,
                startedAt: Date(),
                ownsProcessGroup: ownsProcessGroup
            )
        )
        state.pid = pid
        if selectedPort != 0 {
            state.url = URL(string: "http://127.0.0.1:\(selectedPort)")
        }

        startupTask = Task { try await waitUntilHealthy() }
        do {
            try await startupTask?.value
            guard process.isRunning else {
                throw LauncherError.serviceExited("The process ended before it became ready.")
            }
            state = ServiceState(phase: .running, url: state.url, pid: pid)
        } catch {
            await stopInternal(updateState: false)
            let message = error.localizedDescription
            state = ServiceState(phase: .failed, message: message)
            throw error
        }
    }

    public func stop() async {
        guard state.phase == .running || state.phase == .starting || process != nil else {
            state = ServiceState(phase: .stopped)
            return
        }
        state = ServiceState(phase: .stopping, url: state.url, pid: state.pid)
        await stopInternal(updateState: true)
    }

    public func restart(
        runtime: RuntimeInstallation,
        workspace: URL,
        portMode: PortMode,
        preferredPort: Int
    ) async throws {
        await stop()
        try await start(
            runtime: runtime,
            workspace: workspace,
            portMode: portMode,
            preferredPort: preferredPort
        )
    }

    private func waitUntilHealthy() async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            try Task.checkCancellation()
            if let process, !process.isRunning {
                throw LauncherError.serviceExited("Exit code \(process.terminationStatus)")
            }
            if let url = state.url, await Self.isHealthy(url) { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw LauncherError.startupTimedOut
    }

    private func consumeOutput(_ output: String) {
        logs.append(output)
        guard state.url == nil else { return }
        let pattern = #"dsh web:\s*(http://[^\s]+)"#
        guard let range = output.range(of: pattern, options: .regularExpression) else { return }
        let match = String(output[range])
        guard let separator = match.range(of: "http://") else { return }
        state.url = URL(string: String(match[separator.lowerBound...]))
    }

    private func processDidTerminate(_ completed: Process) {
        if let pipe = completed.standardOutput as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        process = nil
        clearOwnedProcess()
        guard !expectedStop else { return }
        let message = "DSH exited with status \(completed.terminationStatus)."
        logs.append("\n\(message)\n")
        state = ServiceState(phase: .failed, message: message)
    }

    private func stopInternal(updateState: Bool) async {
        startupTask?.cancel()
        startupTask = nil
        expectedStop = true
        guard let runningProcess = process else {
            clearOwnedProcess()
            if updateState { state = ServiceState(phase: .stopped) }
            return
        }

        if ownsProcessGroup {
            kill(-runningProcess.processIdentifier, SIGTERM)
        } else {
            runningProcess.terminate()
        }

        let deadline = Date().addingTimeInterval(5)
        while runningProcess.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if runningProcess.isRunning {
            if ownsProcessGroup {
                kill(-runningProcess.processIdentifier, SIGKILL)
            } else {
                kill(runningProcess.processIdentifier, SIGKILL)
            }
        }
        if let pipe = runningProcess.standardOutput as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        process = nil
        ownsProcessGroup = false
        clearOwnedProcess()
        if updateState { state = ServiceState(phase: .stopped) }
    }

    private func persistOwnedProcess(_ owned: OwnedProcess) {
        try? fileManager.createDirectory(at: paths.applicationSupportURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(owned) else { return }
        try? data.write(to: paths.processOwnershipURL, options: .atomic)
    }

    private func loadOwnedProcess() -> OwnedProcess? {
        guard let data = try? Data(contentsOf: paths.processOwnershipURL) else { return nil }
        return try? JSONDecoder().decode(OwnedProcess.self, from: data)
    }

    private func clearOwnedProcess() {
        try? fileManager.removeItem(at: paths.processOwnershipURL)
    }

    nonisolated private static func processCommand(pid: Int32) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", String(pid), "-o", "command="]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        } catch {
            return ""
        }
    }

    nonisolated private static func isHealthy(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<500).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
