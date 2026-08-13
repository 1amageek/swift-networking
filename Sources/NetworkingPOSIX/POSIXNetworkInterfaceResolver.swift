#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import NetworkingCore
import NetworkingDatagram

/// Resolves platform interface names without exposing POSIX types upstream.
public enum POSIXNetworkInterfaceResolver {
    public static func index(
        named name: String
    ) throws(DatagramError) -> NetworkInterfaceIndex {
        let rawValue = name.withCString { if_nametoindex($0) }
        guard rawValue != 0 else {
            throw .networkInterfaceNotFound(name)
        }
        do {
            return try NetworkInterfaceIndex(rawValue: rawValue)
        } catch {
            throw .networkInterfaceNotFound(name)
        }
    }

    /// Returns the first active multicast-capable non-loopback interface.
    public static func defaultMulticastIndex(
        for family: IPAddressFamily
    ) throws(DatagramError) -> NetworkInterfaceIndex {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            throw .backendFailure(
                operation: .multicast,
                code: Int(posixErrno),
                terminal: false
            )
        }
        defer { freeifaddrs(interfaces) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr else { continue }
            let expectedFamily = family == .ipv4 ? AF_INET : AF_INET6
            guard Int32(address.pointee.sa_family) == expectedFamily else { continue }

            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & Int32(IFF_UP)) != 0,
                  (flags & Int32(IFF_MULTICAST)) != 0,
                  (flags & Int32(IFF_LOOPBACK)) == 0
            else {
                continue
            }

            let rawValue = if_nametoindex(current.pointee.ifa_name)
            guard rawValue != 0 else { continue }
            do {
                return try NetworkInterfaceIndex(rawValue: rawValue)
            } catch {
                continue
            }
        }

        throw .networkInterfaceNotFound("default multicast interface")
    }
}

#endif
