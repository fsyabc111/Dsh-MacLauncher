import Combine
import Foundation

public enum SensitiveDataRedactor {
    private static let assignments = try! NSRegularExpression(
        pattern: "(?i)(api[_-]?key|authorization|token|password)(\\s*[:=]\\s*)([^\\s,;]+)"
    )
    private static let bearer = try! NSRegularExpression(
        pattern: "(?i)bearer\\s+[A-Za-z0-9._~+\\-/]+=*"
    )
    private static let secretKey = try! NSRegularExpression(
        pattern: "\\b(?:sk|ds)-[A-Za-z0-9_-]{12,}\\b"
    )

    public static func redact(_ input: String) -> String {
        var output = replace(bearer, in: input, template: "Bearer <redacted>")
        output = replace(assignments, in: output, template: "$1$2<redacted>")
        return replace(secretKey, in: output, template: "<redacted-key>")
    }

    private static func replace(
        _ expression: NSRegularExpression,
        in value: String,
        template: String
    ) -> String {
        expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: template
        )
    }
}

@MainActor
public final class LogStore: ObservableObject {
    @Published public private(set) var text = ""

    public let directoryURL: URL
    public let maxFileSize: UInt64
    public let retainedFileCount: Int
    private let fileManager: FileManager

    public init(
        directoryURL: URL? = nil,
        maxFileSize: UInt64 = 10 * 1_024 * 1_024,
        retainedFileCount: Int = 5,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.maxFileSize = maxFileSize
        self.retainedFileCount = retainedFileCount
        self.directoryURL = directoryURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DSH Launcher", isDirectory: true)
        try? fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
    }

    public var currentLogURL: URL {
        directoryURL.appendingPathComponent("dsh-launcher.log")
    }

    public func append(_ rawValue: String) {
        guard !rawValue.isEmpty else { return }
        let value = SensitiveDataRedactor.redact(rawValue)
        text.append(value)
        if text.count > 200_000 {
            text.removeFirst(text.count - 200_000)
        }

        rotateIfNeeded(addingBytes: UInt64(value.utf8.count))
        if !fileManager.fileExists(atPath: currentLogURL.path) {
            fileManager.createFile(atPath: currentLogURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: currentLogURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(value.utf8))
        } catch {
            return
        }
    }

    public func clear() {
        text = ""
        try? Data().write(to: currentLogURL, options: .atomic)
    }

    public func logFileURLs() -> [URL] {
        var urls = [currentLogURL]
        urls.append(contentsOf: (1..<retainedFileCount).map {
            directoryURL.appendingPathComponent("dsh-launcher.log.\($0)")
        })
        return urls.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func rotateIfNeeded(addingBytes: UInt64) {
        let size = ((try? fileManager.attributesOfItem(atPath: currentLogURL.path)[.size]) as? NSNumber)?.uint64Value ?? 0
        guard size + addingBytes > maxFileSize else { return }

        if retainedFileCount > 1 {
            for index in stride(from: retainedFileCount - 1, through: 1, by: -1) {
                let destination = directoryURL.appendingPathComponent("dsh-launcher.log.\(index)")
                let source = index == 1
                    ? currentLogURL
                    : directoryURL.appendingPathComponent("dsh-launcher.log.\(index - 1)")
                try? fileManager.removeItem(at: destination)
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.moveItem(at: source, to: destination)
                }
            }
        } else {
            try? fileManager.removeItem(at: currentLogURL)
        }
    }
}
