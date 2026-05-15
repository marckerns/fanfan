//
//  File: SMCDaemonClient.swift / 文件：SMCDaemonClient.swift
//  Target: fanfan / 目标：fanfan
//
//  Created by haobin on 2026/5/15. / 创建者：haobin，日期：2026/5/15。
//  Description: Fast fan-write path through the root LaunchDaemon. / 描述：通过 root LaunchDaemon 执行风扇写入的快速路径。
//

import Darwin
import Foundation

enum SMCDaemonClient {
    private static let socketPath = "/var/run/fanfan-smcd.sock"

    static func ping() -> Bool {
        send("PING")
    }

    static func setFanSpeed(fanIndex: Int, rpm: Int) -> Bool {
        send("SET \(fanIndex) \(rpm)")
    }

    static func setFanAuto(fanIndex: Int) -> Bool {
        send("AUTO \(fanIndex)")
    }

    private static func send(_ command: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(socketPath.utf8)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < pathCapacity else { return false }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { rebound in
                for (idx, byte) in pathBytes.enumerated() {
                    rebound[idx] = CChar(bitPattern: byte)
                }
                rebound[pathBytes.count] = 0
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return false }

        let payload = command + "\n"
        guard payload.withCString({ cString in
            Darwin.write(fd, cString, strlen(cString))
        }) == payload.utf8.count else {
            return false
        }

        var response = [UInt8](repeating: 0, count: 64)
        let readCount = Darwin.read(fd, &response, response.count - 1)
        guard readCount > 0 else { return false }

        let text = String(decoding: response.prefix(Int(readCount)), as: UTF8.self)
        return text.hasPrefix("OK")
    }
}
