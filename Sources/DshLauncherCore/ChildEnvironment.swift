import Foundation

/// Builds the environment for the spawned DSH service process.
///
/// GUI apps launched from Finder/Dock inherit launchd's minimal PATH
/// (`/usr/bin:/bin:/usr/sbin:/sbin`), so tools the DSH web server spawns at
/// runtime — pnpm, npm, node, git — are not found, and plugin features such
/// as the in-UI plugin market fail with "pnpm not found on PATH". The
/// launcher therefore composes a PATH for the child: whatever PATH it was
/// started with (richest when launched from a terminal), the runtime's own
/// node bin (guarantees `node`), well-known user tool directories that
/// exist on disk, Homebrew locations, user-configured extras, and the system
/// directories last.
public enum ChildEnvironment {

    /// Well-known user tool directories, resolved against the home directory
    /// and included only when they exist on disk.
    public static let wellKnownToolDirectories: [String] = [
        ".npm-global/bin",          // npm global installs (npm config get prefix)
        ".local/share/pnpm",        // pnpm standalone (Linux-style layout)
        "Library/pnpm",             // pnpm standalone (macOS layout)
        ".volta/bin",               // Volta
        ".bun/bin",                 // Bun
        ".cargo/bin",               // Cargo
        ".local/bin",               // user scripts
        ".local/share/mise/shims",  // mise
        ".asdf/shims",              // asdf
    ]

    /// Homebrew package manager bin directories.
    public static let homebrewDirectories = [
        "/opt/homebrew/bin",  // Apple Silicon
        "/usr/local/bin",     // Intel
    ]

    /// System directories, always appended last.
    public static let systemDirectories = [
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    /// Compose the PATH for the child process.
    ///
    /// - Parameters:
    ///   - nodeBinDirectory: directory containing the runtime's node
    ///     executable; always included so `node` resolves for node-script
    ///     tools like pnpm.
    ///   - homeDirectory: user's home directory used to resolve `~`-relative
    ///     tool directories.
    ///   - existingPath: the launcher's own PATH; kept first when present.
    ///   - extraEntries: user-configured extra directories (from settings),
    ///     appended after well-known locations.
    ///   - fileManager: file system probe for well-known directories.
    /// - Returns: the composed PATH, deduplicated in order.
    public static func path(
        nodeBinDirectory: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        existingPath: String?,
        extraEntries: [String],
        fileManager: FileManager = .default
    ) -> String {
        var entries: [String] = []
        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !entries.contains(trimmed) else { return }
            entries.append(trimmed)
        }

        // 1. Whatever the launcher already had.
        existingPath?
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
            .forEach(append)

        // 2. The runtime's own node bin — always present, guarantees `node`.
        append(nodeBinDirectory.path)

        // 3. Well-known user tool dirs that exist on disk.
        for relative in wellKnownToolDirectories {
            let directory = homeDirectory.appendingPathComponent(relative, isDirectory: true)
            if fileManager.fileExists(atPath: directory.path) {
                append(directory.path)
            }
        }

        // 4. nvm: bin of the newest installed node version, when present.
        let nvmRoot = homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmRoot.path),
           let newest = versions
            .filter({ fileManager.fileExists(atPath: nvmRoot.appendingPathComponent($0).appendingPathComponent("bin").path) })
            .sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending })
            .first {
            append(nvmRoot.appendingPathComponent(newest).appendingPathComponent("bin").path)
        }

        // 5. Homebrew.
        homebrewDirectories.forEach(append)

        // 6. User-configured extras.
        extraEntries.forEach(append)

        // 7. System dirs last — system tools stay reachable no matter what.
        systemDirectories.forEach(append)

        return entries.joined(separator: ":")
    }
}
