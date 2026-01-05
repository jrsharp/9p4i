import Foundation
import Combine

/// DFU state machine for firmware updates via 9P
enum DFUState: Equatable {
    case idle
    case reading          // Reading current firmware status
    case erasing          // Device is erasing flash
    case uploading        // Uploading firmware binary
    case verifying        // Verifying uploaded image
    case waitingReboot    // Ready to reboot
    case rebooting        // Reboot triggered
    case success          // Update complete (after reboot)
    case error(String)    // Error occurred

    var description: String {
        switch self {
        case .idle: return "Ready"
        case .reading: return "Reading status..."
        case .erasing: return "Erasing flash..."
        case .uploading: return "Uploading firmware..."
        case .verifying: return "Verifying..."
        case .waitingReboot: return "Ready to reboot"
        case .rebooting: return "Rebooting..."
        case .success: return "Update complete!"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isWorking: Bool {
        switch self {
        case .reading, .erasing, .uploading, .verifying, .rebooting:
            return true
        default:
            return false
        }
    }
}

/// Information about the device's current firmware
struct FirmwareStatus {
    let state: String       // idle, receiving, complete, error
    let currentVersion: String?
    let bytesReceived: UInt32
    let isConfirmed: Bool

    static func parse(_ text: String) -> FirmwareStatus {
        var state = "unknown"
        var version: String? = nil
        var bytes: UInt32 = 0
        var confirmed = false

        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0])
            let value = String(parts[1])

            switch key {
            case "state": state = value
            case "current": version = value
            case "bytes": bytes = UInt32(value) ?? 0
            case "confirmed": confirmed = (value == "yes")
            default: break
            }
        }

        return FirmwareStatus(
            state: state,
            currentVersion: version,
            bytesReceived: bytes,
            isConfirmed: confirmed
        )
    }
}

/// Manages firmware updates via 9P filesystem
@MainActor
class DFUManager: ObservableObject {
    @Published var state: DFUState = .idle
    @Published var progress: Double = 0
    @Published var firmwareStatus: FirmwareStatus?
    @Published var bytesTransferred: UInt64 = 0
    @Published var totalBytes: UInt64 = 0

    private weak var client: NinePClient?

    // 9P paths for DFU operations
    private let firmwarePath = "/dev/firmware"
    private let rebootPath = "/dev/reboot"
    private let confirmPath = "/dev/confirm"

    init(client: NinePClient? = nil) {
        self.client = client
    }

    func setClient(_ client: NinePClient) {
        self.client = client
    }

    /// Read current firmware status from device
    func readStatus() async {
        guard let client = client else {
            state = .error("Not connected")
            return
        }

        state = .reading

        do {
            let data = try await client.readFile(path: firmwarePath)
            if let text = String(data: data, encoding: .utf8) {
                firmwareStatus = FirmwareStatus.parse(text)
                state = .idle
            } else {
                state = .error("Invalid status response")
            }
        } catch {
            state = .error("Failed to read status: \(error.localizedDescription)")
        }
    }

    /// Upload firmware binary to device
    func uploadFirmware(data: Data) async {
        guard let client = client else {
            state = .error("Not connected")
            return
        }

        state = .uploading
        progress = 0
        bytesTransferred = 0
        totalBytes = UInt64(data.count)

        do {
            print("🔧 [DFU] Starting firmware upload: \(data.count) bytes")

            try await client.writeFile(path: firmwarePath, data: data) { [weak self] prog in
                Task { @MainActor in
                    self?.progress = prog
                    self?.bytesTransferred = UInt64(Double(data.count) * prog)
                }
            }

            print("✅ [DFU] Firmware upload complete")
            state = .waitingReboot

            // Refresh status
            await readStatus()

        } catch {
            print("❌ [DFU] Upload failed: \(error)")
            state = .error("Upload failed: \(error.localizedDescription)")
        }
    }

    /// Upload firmware from a file URL
    func uploadFirmware(from url: URL) async {
        do {
            let needsSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            await uploadFirmware(data: data)
        } catch {
            state = .error("Failed to read file: \(error.localizedDescription)")
        }
    }

    /// Reboot device to apply firmware update
    func reboot() async {
        guard let client = client else {
            state = .error("Not connected")
            return
        }

        state = .rebooting

        do {
            print("🔧 [DFU] Triggering reboot...")
            try await client.writeFile(path: rebootPath, data: Data("1".utf8))
            print("✅ [DFU] Reboot triggered")
            // Device will disconnect - connection handler should update state
        } catch {
            // Reboot may cause disconnect before response - that's OK
            print("⚠️ [DFU] Reboot response: \(error.localizedDescription)")
            // Consider this a success if it was a disconnect
            if case NinePError.notConnected = error {
                state = .success
            } else {
                state = .error("Reboot failed: \(error.localizedDescription)")
            }
        }
    }

    /// Confirm the running image (make it permanent)
    func confirmImage() async {
        guard let client = client else {
            state = .error("Not connected")
            return
        }

        do {
            print("🔧 [DFU] Confirming image...")
            try await client.writeFile(path: confirmPath, data: Data("1".utf8))
            print("✅ [DFU] Image confirmed")

            // Refresh status
            await readStatus()
        } catch {
            state = .error("Confirm failed: \(error.localizedDescription)")
        }
    }

    /// Reset DFU state
    func reset() {
        state = .idle
        progress = 0
        bytesTransferred = 0
        totalBytes = 0
    }
}
