#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import NetworkingCore

enum POSIXSocketAddressCodec {
    static func encode(
        _ endpoint: IPSocketEndpoint
    ) -> (storage: sockaddr_storage, length: socklen_t) {
        var storage = sockaddr_storage()

        switch endpoint.address {
        case let .v4(a, b, c, d):
            var address = sockaddr_in()
            #if canImport(Darwin)
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            #endif
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = endpoint.port.bigEndian
            let packed = (UInt32(a) << 24)
                | (UInt32(b) << 16)
                | (UInt32(c) << 8)
                | UInt32(d)
            address.sin_addr.s_addr = packed.bigEndian
            withUnsafeMutableBytes(of: &storage) { destination in
                withUnsafeBytes(of: address) { source in
                    destination.copyMemory(from: source)
                }
            }
            return (storage, socklen_t(MemoryLayout<sockaddr_in>.size))

        case let .v6(octets):
            var address = sockaddr_in6()
            #if canImport(Darwin)
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            #endif
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = endpoint.port.bigEndian
            address.sin6_scope_id = endpoint.scopeID?.rawValue ?? 0
            withUnsafeMutableBytes(of: &address.sin6_addr) { destination in
                destination[0] = octets.b0
                destination[1] = octets.b1
                destination[2] = octets.b2
                destination[3] = octets.b3
                destination[4] = octets.b4
                destination[5] = octets.b5
                destination[6] = octets.b6
                destination[7] = octets.b7
                destination[8] = octets.b8
                destination[9] = octets.b9
                destination[10] = octets.b10
                destination[11] = octets.b11
                destination[12] = octets.b12
                destination[13] = octets.b13
                destination[14] = octets.b14
                destination[15] = octets.b15
            }
            withUnsafeMutableBytes(of: &storage) { destination in
                withUnsafeBytes(of: address) { source in
                    destination.copyMemory(from: source)
                }
            }
            return (storage, socklen_t(MemoryLayout<sockaddr_in6>.size))
        }
    }

    static func decode(_ storage: sockaddr_storage) -> IPSocketEndpoint? {
        var mutableStorage = storage

        if Int32(storage.ss_family) == AF_INET {
            let address = withUnsafeBytes(of: &mutableStorage) {
                $0.loadUnaligned(as: sockaddr_in.self)
            }
            let host = UInt32(bigEndian: address.sin_addr.s_addr)
            return IPSocketEndpoint(
                ipv4: UInt8((host >> 24) & 0xFF),
                UInt8((host >> 16) & 0xFF),
                UInt8((host >> 8) & 0xFF),
                UInt8(host & 0xFF),
                port: UInt16(bigEndian: address.sin_port)
            )
        }

        if Int32(storage.ss_family) == AF_INET6 {
            let address = withUnsafeBytes(of: &mutableStorage) {
                $0.loadUnaligned(as: sockaddr_in6.self)
            }
            var mutableAddress = address.sin6_addr
            let octets = withUnsafeBytes(of: &mutableAddress) { bytes in
                InlineIPv6Address(
                    bytes[0], bytes[1], bytes[2], bytes[3],
                    bytes[4], bytes[5], bytes[6], bytes[7],
                    bytes[8], bytes[9], bytes[10], bytes[11],
                    bytes[12], bytes[13], bytes[14], bytes[15]
                )
            }
            let scope: NetworkInterfaceIndex?
            if address.sin6_scope_id == 0 {
                scope = nil
            } else {
                do {
                    scope = try NetworkInterfaceIndex(rawValue: address.sin6_scope_id)
                } catch {
                    return nil
                }
            }
            return IPSocketEndpoint(
                ipv6: octets,
                port: UInt16(bigEndian: address.sin6_port),
                scopeID: scope
            )
        }

        return nil
    }

    static func family(of endpoint: IPSocketEndpoint) -> Int32 {
        endpoint.address.isIPv4 ? AF_INET : AF_INET6
    }
}

#endif
