#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@inline(__always)
var posixDatagramSocketType: Int32 {
    #if canImport(Darwin)
    SOCK_DGRAM
    #else
    Int32(SOCK_DGRAM.rawValue)
    #endif
}

@inline(__always)
func posixBind(
    _ descriptor: Int32,
    _ address: UnsafePointer<sockaddr>,
    _ length: socklen_t
) -> Int32 {
    bind(descriptor, address, length)
}

@inline(__always)
func posixSetSocketOption(
    _ descriptor: Int32,
    level: Int32,
    option: Int32,
    value: UnsafeRawPointer?,
    length: socklen_t
) -> Int32 {
    setsockopt(descriptor, level, option, value, length)
}

@inline(__always)
func posixSendTo(
    _ descriptor: Int32,
    buffer: UnsafeRawPointer?,
    length: Int,
    address: UnsafePointer<sockaddr>,
    addressLength: socklen_t
) -> Int {
    sendto(descriptor, buffer, length, 0, address, addressLength)
}

@inline(__always)
func posixReceiveFrom(
    _ descriptor: Int32,
    buffer: UnsafeMutableRawPointer?,
    length: Int,
    address: UnsafeMutablePointer<sockaddr>,
    addressLength: UnsafeMutablePointer<socklen_t>
) -> Int {
    recvfrom(descriptor, buffer, length, 0, address, addressLength)
}

@inline(__always)
func posixWrite(
    _ descriptor: Int32,
    buffer: UnsafeRawPointer?,
    length: Int
) -> Int {
    write(descriptor, buffer, length)
}

@inline(__always)
func posixClose(_ descriptor: Int32) -> Int32 {
    close(descriptor)
}

@inline(__always)
func posixShutdown(_ descriptor: Int32) -> Int32 {
    #if canImport(Darwin)
    shutdown(descriptor, SHUT_RDWR)
    #else
    shutdown(descriptor, Int32(SHUT_RDWR))
    #endif
}

@inline(__always)
var posixErrno: Int32 {
    #if canImport(Darwin)
    __error().pointee
    #else
    __errno_location().pointee
    #endif
}

#endif
