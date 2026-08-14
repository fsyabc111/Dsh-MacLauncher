import Darwin
import XCTest
@testable import DshLauncherCore

final class PortResolverTests: XCTestCase {
    func testAutomaticModeFallsBackToDynamicPort() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(descriptor, $0, &length)
            }
        }
        let port = Int(UInt16(bigEndian: bound.sin_port))

        XCTAssertEqual(try PortResolver.launchPort(mode: .automatic, preferredPort: port), 0)
        XCTAssertThrowsError(try PortResolver.launchPort(mode: .fixed, preferredPort: port))
    }
}
