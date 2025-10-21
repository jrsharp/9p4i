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

    // 9P Service UUID to filter devices
    private let ninePServiceUUID = CBUUID(string: "39500001-FEED-4A91-BA88-A1E0F6E4C001")

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
        // Use main queue for CBCentralManager to ensure proper run loop
        centralManager = CBCentralManager(delegate: self, queue: .main)
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
        print("🔴 [L2CAP] Disconnecting from peripheral...")
        if let peripheral = connectedPeripheral {
            print("🔴 [L2CAP] Cancelling connection to: \(peripheral.name ?? "Unknown")")
            centralManager.cancelPeripheralConnection(peripheral)
        }
        closeL2CAPChannel()
        connectedPeripheral = nil
        connectionState = "Disconnected"
        print("✅ [L2CAP] Disconnected")
    }

    func send(data: Data) {
        guard let channel = l2capChannel else {
            print("❌ [L2CAP] No L2CAP channel open")
            return
        }

        guard let outputStream = channel.outputStream else {
            print("❌ [L2CAP] Output stream not available")
            return
        }

        print("📤 [L2CAP] Sending \(data.count) bytes")
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let baseAddress = buffer.baseAddress else { return }
            let bytesWritten = outputStream.write(
                baseAddress.assumingMemoryBound(to: UInt8.self),
                maxLength: data.count
            )
            if bytesWritten == data.count {
                print("✅ [L2CAP] Successfully sent \(bytesWritten) bytes")
            } else {
                print("⚠️ [L2CAP] Sent \(bytesWritten) bytes (expected \(data.count))")
            }
        }
    }

    // MARK: - Peripheral Management

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }

        discoveredPeripherals.removeAll()
        discoveredPeripheralIDs.removeAll()
        isScanning = true

        print("🔍 [BLE] Starting scan for 9P service: \(ninePServiceUUID)")
        centralManager.scanForPeripherals(withServices: [ninePServiceUUID], options: [
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

        // Get name from scan response data (CBAdvertisementDataLocalNameKey) or peripheral.name fallback
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let deviceName = localName ?? peripheral.name ?? "Unknown"

        print("🔍 [BLE] Discovered: \(deviceName) - \(peripheral.identifier)")
        if localName != nil {
            print("   └─ Name from scan response data: \(localName!)")
        } else if peripheral.name != nil {
            print("   └─ Name from peripheral: \(peripheral.name!)")
        }

        discoveredPeripheralIDs.insert(peripheral.identifier)
        DispatchQueue.main.async {
            self.discoveredPeripherals.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ [BLE] Connected to peripheral: \(peripheral.name ?? "Unknown")")
        peripheral.delegate = self
        DispatchQueue.main.async {
            self.connectionState = "Opening L2CAP..."
        }
        print("🔌 [BLE] Opening L2CAP channel on PSM: \(self.psm)")
        peripheral.openL2CAPChannel(psm)
    }

    func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        print("⚠️ [BLE] Disconnected from peripheral: \(error?.localizedDescription ?? "No error")")
        DispatchQueue.main.async {
            self.connectionState = "Disconnected"
        }
        closeL2CAPChannel()
        delegate?.transport(self, didDisconnectWithError: error)
    }

    func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        print("❌ [BLE] Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        DispatchQueue.main.async {
            self.connectionState = "Failed"
        }
        connectContinuation?.resume(throwing: error ?? TransportError.connectionFailed)
        connectContinuation = nil
    }
}

// MARK: - CBPeripheralDelegate

extension L2CAPTransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        print("🔌 [BLE] didOpen L2CAP channel callback received")

        if let error = error {
            print("❌ [BLE] Failed to open L2CAP: \(error)")
            DispatchQueue.main.async {
                self.connectionState = "L2CAP Failed"
            }
            connectContinuation?.resume(throwing: error)
            connectContinuation = nil
            return
        }

        guard let channel = channel else {
            print("❌ [BLE] L2CAP channel is nil")
            DispatchQueue.main.async {
                self.connectionState = "Channel Failed"
            }
            connectContinuation?.resume(throwing: TransportError.channelFailed)
            connectContinuation = nil
            return
        }

        print("✅ [BLE] L2CAP channel opened successfully, PSM: \(channel.psm)")
        l2capChannel = channel

        // Schedule streams on main thread to avoid priority inversion
        DispatchQueue.main.async {
            channel.inputStream.delegate = self
            channel.outputStream.delegate = self
            channel.inputStream.schedule(in: .main, forMode: .default)
            channel.outputStream.schedule(in: .main, forMode: .default)
            channel.inputStream.open()
            channel.outputStream.open()

            print("✅ [BLE] Streams opened, resuming continuation")
            self.connectionState = "Connected"
            self.connectContinuation?.resume()
            self.connectContinuation = nil
            print("✅ [BLE] Connection complete!")
        }
    }
}

// MARK: - StreamDelegate

extension L2CAPTransport: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        print("📨 [L2CAP] Stream event: \(eventCode)")
        switch eventCode {
        case .hasBytesAvailable:
            guard let inputStream = aStream as? InputStream else { return }

            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)

            print("📥 [L2CAP] Read \(bytesRead) bytes from stream")
            if bytesRead > 0 {
                rxBuffer.append(Data(buffer[..<bytesRead]))
                print("📥 [L2CAP] RX buffer now has \(rxBuffer.count) bytes")
                processRxBuffer()
            }

        case .errorOccurred:
            if let error = aStream.streamError {
                print("❌ [L2CAP] Stream error: \(error)")
                delegate?.transport(self, didDisconnectWithError: error)
            }

        case .endEncountered:
            print("⚠️ [L2CAP] Stream end encountered")
            closeL2CAPChannel()
            delegate?.transport(self, didDisconnectWithError: nil)

        default:
            print("📨 [L2CAP] Other stream event: \(eventCode)")
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
