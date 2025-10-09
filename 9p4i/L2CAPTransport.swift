import Foundation
import CoreBluetooth
import Combine

// L2CAP Transport implementation for 9P
class L2CAPTransport: NSObject, NinePTransport, ObservableObject {
    weak var delegate: NinePTransportDelegate?

    @Published var isScanning = false
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var connectionState: String = "Disconnected"

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var l2capChannel: CBL2CAPChannel?
    private var discoveredPeripheralIDs = Set<UUID>()
    private let psm: UInt16

    // RX State Machine
    private var rxBuffer = Data()
    private var rxState: RXState = .waitingForSize
    private var expectedSize: UInt32 = 0

    private enum RXState {
        case waitingForSize
        case waitingForMessage
    }

    private var connectContinuation: CheckedContinuation<Void, Error>?

    init(psm: UInt16 = 0x0009) {
        self.psm = psm
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - NinePTransport Protocol

    func connect() async throws {
        // This assumes a peripheral is already selected
        guard let peripheral = connectedPeripheral else {
            throw TransportError.noPeripheralSelected
        }

        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
        }
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        closeL2CAPChannel()
        connectedPeripheral = nil
        connectionState = "Disconnected"
    }

    func send(data: Data) {
        guard let channel = l2capChannel else {
            print("No L2CAP channel open")
            return
        }

        guard let outputStream = channel.outputStream else {
            print("Output stream not available")
            return
        }

        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = outputStream.write(
                baseAddress.assumingMemoryBound(to: UInt8.self),
                maxLength: data.count
            )
        }
    }

    // MARK: - Peripheral Management

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }

        discoveredPeripherals.removeAll()
        discoveredPeripheralIDs.removeAll()
        isScanning = true

        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    func selectPeripheral(_ peripheral: CBPeripheral) {
        stopScanning()
        connectionState = "Connecting..."
        connectedPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }

    // MARK: - Private Methods

    private func closeL2CAPChannel() {
        if let channel = l2capChannel {
            channel.inputStream.close()
            channel.outputStream.close()
            l2capChannel = nil
        }
        rxBuffer.removeAll()
        rxState = .waitingForSize
    }

    private func processRxBuffer() {
        while true {
            switch rxState {
            case .waitingForSize:
                guard rxBuffer.count >= 4 else { return }

                expectedSize = rxBuffer.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
                }

                guard expectedSize >= 7 && expectedSize <= 8192 else {
                    print("Invalid message size: \(expectedSize)")
                    rxBuffer.removeAll()
                    rxState = .waitingForSize
                    return
                }

                rxState = .waitingForMessage

            case .waitingForMessage:
                guard rxBuffer.count >= expectedSize else { return }

                let msgData = rxBuffer.prefix(Int(expectedSize))
                rxBuffer.removeFirst(Int(expectedSize))

                if let msg = NinePMessage(data: msgData) {
                    delegate?.transport(self, didReceive: msg)
                }

                rxState = .waitingForSize
                expectedSize = 0
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension L2CAPTransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth powered on")
        case .poweredOff:
            print("Bluetooth powered off")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didDiscover peripheral: CBPeripheral,
                       advertisementData: [String : Any],
                       rssi RSSI: NSNumber) {
        guard !discoveredPeripheralIDs.contains(peripheral.identifier) else { return }

        discoveredPeripheralIDs.insert(peripheral.identifier)
        DispatchQueue.main.async {
            self.discoveredPeripherals.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        connectionState = "Opening L2CAP..."
        peripheral.openL2CAPChannel(psm)
    }

    func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        connectionState = "Disconnected"
        closeL2CAPChannel()
        delegate?.transport(self, didDisconnectWithError: error)
    }

    func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        connectionState = "Failed"
        connectContinuation?.resume(throwing: error ?? TransportError.connectionFailed)
        connectContinuation = nil
    }
}

// MARK: - CBPeripheralDelegate

extension L2CAPTransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        if let error = error {
            print("Failed to open L2CAP: \(error)")
            connectContinuation?.resume(throwing: error)
            connectContinuation = nil
            return
        }

        guard let channel = channel else {
            connectContinuation?.resume(throwing: TransportError.channelFailed)
            connectContinuation = nil
            return
        }

        l2capChannel = channel

        channel.inputStream.delegate = self
        channel.outputStream.delegate = self
        channel.inputStream.schedule(in: .current, forMode: .default)
        channel.outputStream.schedule(in: .current, forMode: .default)
        channel.inputStream.open()
        channel.outputStream.open()

        connectionState = "Connected"
        connectContinuation?.resume()
        connectContinuation = nil
    }
}

// MARK: - StreamDelegate

extension L2CAPTransport: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            guard let inputStream = aStream as? InputStream else { return }

            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)

            if bytesRead > 0 {
                rxBuffer.append(Data(buffer[..<bytesRead]))
                processRxBuffer()
            }

        case .errorOccurred:
            if let error = aStream.streamError {
                print("Stream error: \(error)")
                delegate?.transport(self, didDisconnectWithError: error)
            }

        case .endEncountered:
            closeL2CAPChannel()
            delegate?.transport(self, didDisconnectWithError: nil)

        default:
            break
        }
    }
}

// MARK: - Errors

enum TransportError: LocalizedError {
    case noPeripheralSelected
    case connectionFailed
    case channelFailed

    var errorDescription: String? {
        switch self {
        case .noPeripheralSelected:
            return "No peripheral selected"
        case .connectionFailed:
            return "Connection failed"
        case .channelFailed:
            return "L2CAP channel failed to open"
        }
    }
}
