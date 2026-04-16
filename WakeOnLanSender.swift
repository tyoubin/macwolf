import Foundation
import Network

enum WakeOnLanError: Error, LocalizedError {
    case invalidMacAddress
    case sendFailure(Error)

    var errorDescription: String? {
        switch self {
        case .invalidMacAddress:
            return "Invalid MAC address."
        case .sendFailure(let error):
            return "Failed to send packet: \(error.localizedDescription)"
        }
    }
}

protocol WakeOnLanSending {
    func sendWakePacket(to macAddress: String, completion: @escaping @Sendable (Result<Void, WakeOnLanError>) -> Void)
}

enum WakeOnLanPacketBuilder {
    static func buildPacket(macAddress: String) throws -> Data {
        let cleanMac = macAddress
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")

        guard cleanMac.count == 12 else {
            throw WakeOnLanError.invalidMacAddress
        }

        var macBytes = [UInt8]()
        macBytes.reserveCapacity(6)
        for i in stride(from: 0, to: cleanMac.count, by: 2) {
            let start = cleanMac.index(cleanMac.startIndex, offsetBy: i)
            let end = cleanMac.index(start, offsetBy: 2)
            let hex = String(cleanMac[start..<end])
            guard let byte = UInt8(hex, radix: 16) else {
                throw WakeOnLanError.invalidMacAddress
            }
            macBytes.append(byte)
        }

        guard macBytes.count == 6 else {
            throw WakeOnLanError.invalidMacAddress
        }

        var packet = Data()
        packet.append(contentsOf: [UInt8](repeating: 0xFF, count: 6))
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }
}

final class WakeOnLanSender: WakeOnLanSending {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = .global()) {
        self.queue = queue
    }

    func sendWakePacket(to macAddress: String, completion: @escaping @Sendable (Result<Void, WakeOnLanError>) -> Void) {
        do {
            let packet = try WakeOnLanPacketBuilder.buildPacket(macAddress: macAddress)
            let connection = NWConnection(host: "255.255.255.255", port: NWEndpoint.Port(integerLiteral: 9), using: .udp)
            connection.start(queue: queue)
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error {
                    completion(.failure(.sendFailure(error)))
                } else {
                    completion(.success(()))
                }
                connection.cancel()
            })
        } catch let wolError as WakeOnLanError {
            completion(.failure(wolError))
        } catch {
            completion(.failure(.invalidMacAddress))
        }
    }
}
