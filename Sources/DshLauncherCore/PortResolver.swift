import Darwin
import Foundation

public enum PortResolver {
    public static func launchPort(mode: PortMode, preferredPort: Int) throws -> Int {
        let port = min(max(preferredPort, 1), 65_535)
        if isAvailable(port) { return port }
        if mode == .automatic { return 0 }
        throw LauncherError.portUnavailable(port)
    }

    public static func isAvailable(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
