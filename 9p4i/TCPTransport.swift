import Foundation
import Network

// TCP Transport implementation for 9P
class TCPTransport: NinePTransport, ObservableObject {
    weak var delegate: NinePTransportDelegate?

    @Published var connectionState: String = "Disconnected"

    private var connection: NWConnection?
    private let host: String
    private let port: UInt16

    // RX State Machine
    private var rxBuffer = Data()
    private var rxState: RXState = .waitingForSize
    private var expectedSize: UInt32 = 0

    private enum RXState {
        case waitingForSize
        case waitingForMessage
    }

    private var connectContinuation: CheckedContinuation<Void, Error>?

    private let queue = DispatchQueue(label: "com.9p4i.tcp", qos: .userInitiated)

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    // MARK: - NinePTransport Protocol

    func connect() async throws {
        await MainActor.run {
            connectionState = "Connecting..."
        }

        print("🔵 Creating TCP connection to \(host):\(port)")

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )

        // Configure TCP parameters to avoid VPN routing for local network
        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.prohibitExpensivePaths = true  // Avoid VPN/cellular
        params.preferNoProxies = true         // Direct connection

        let connection = NWConnection(
            to: endpoint,
            using: params
        )

        self.connection = connection

        return try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation

            connection.stateUpdateHandler = { [weak self] state in
                self?.handleStateChange(state)
            }

            print("🔵 Starting connection on background queue...")
            connection.start(queue: queue)
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        connectionState = "Disconnected"
        rxBuffer.removeAll()
        rxState = .waitingForSize
    }

    func send(data: Data) {
        guard let connection = connection else {
            print("❌ No TCP connection")
            return
        }

        print("📤 Sending \(data.count) bytes: \(data.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))\(data.count > 32 ? "..." : "")")

        connection.send(
            content: data,
            completion: .contentProcessed { error in
                if let error = error {
                    print("❌ Send error: \(error)")
                } else {
                    print("✅ Sent \(data.count) bytes successfully")
                }
            }
        )
    }

    // MARK: - Connection State Handling

    private func handleStateChange(_ state: NWConnection.State) {
        print("🔵 TCP State Change: \(state)")

        switch state {
        case .ready:
            print("✅ TCP Connected - starting receive loop")
            connectionState = "Connected"
            connectContinuation?.resume()
            connectContinuation = nil
            startReceiving()

        case .waiting(let error):
            print("⏳ TCP Waiting: \(error)")
            connectionState = "Waiting..."

        case .failed(let error):
            print("❌ TCP Failed: \(error)")
            connectionState = "Failed"
            connectContinuation?.resume(throwing: error)
            connectContinuation = nil
            delegate?.transport(self, didDisconnectWithError: error)

        case .cancelled:
            print("🔴 TCP Cancelled")
            connectionState = "Disconnected"
            delegate?.transport(self, didDisconnectWithError: nil)

        case .preparing:
            print("🔧 TCP Preparing...")

        case .setup:
            print("🔧 TCP Setup...")

        @unknown default:
            print("⚠️ TCP Unknown state: \(state)")
        }
    }

    // MARK: - Receiving Data

    private func startReceiving() {
        guard let connection = connection else {
            print("⚠️ startReceiving called but connection is nil")
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                print("📥 Received \(data.count) bytes: \(data.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))\(data.count > 32 ? "..." : "")")
                self.rxBuffer.append(data)
                print("📦 RX Buffer now: \(self.rxBuffer.count) bytes")
                self.processRxBuffer()
            }

            if let error = error {
                print("❌ Receive error: \(error)")
                self.delegate?.transport(self, didDisconnectWithError: error)
                return
            }

            if isComplete {
                print("🏁 Stream complete")
                self.delegate?.transport(self, didDisconnectWithError: nil)
                return
            }

            // Continue receiving
            self.startReceiving()
        }
    }

    private func processRxBuffer() {
        while true {
            switch rxState {
            case .waitingForSize:
                print("🔍 State: WAIT_SIZE, buffer has \(rxBuffer.count) bytes")
                guard rxBuffer.count >= 4 else {
                    print("   Need 4 bytes for size, only have \(rxBuffer.count)")
                    return
                }

                expectedSize = rxBuffer.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
                }
                print("📏 Read size field: \(expectedSize) bytes")

                // Validate size
                guard expectedSize >= 7 && expectedSize <= 8192 else {
                    print("❌ Invalid message size: \(expectedSize) (must be 7-8192)")
                    print("   Buffer hex: \(rxBuffer.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))")
                    rxBuffer.removeAll()
                    rxState = .waitingForSize
                    return
                }

                print("✅ Valid size, transitioning to WAIT_MSG")
                rxState = .waitingForMessage

            case .waitingForMessage:
                print("🔍 State: WAIT_MSG, need \(expectedSize) bytes, have \(rxBuffer.count)")
                guard rxBuffer.count >= expectedSize else {
                    print("   Still waiting for \(expectedSize - UInt32(rxBuffer.count)) more bytes")
                    return
                }

                // Extract complete message
                let msgData = rxBuffer.prefix(Int(expectedSize))
                rxBuffer.removeFirst(Int(expectedSize))
                print("✂️ Extracted message, \(rxBuffer.count) bytes remain in buffer")

                // Parse and dispatch
                print("📨 Parsing message...")
                if let msg = NinePMessage(data: msgData) {
                    print("✅ Parsed: \(msg.type.name) tag=\(msg.tag) size=\(msg.size)")
                    print("📤 Dispatching to delegate...")
                    delegate?.transport(self, didReceive: msg)
                    print("✅ Dispatched")
                } else {
                    print("❌ Failed to parse message")
                    print("   Hex: \(msgData.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))")
                }

                // Reset state for next message
                print("🔄 Resetting to WAIT_SIZE")
                rxState = .waitingForSize
                expectedSize = 0
            }
        }
    }
}
