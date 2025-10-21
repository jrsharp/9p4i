import SwiftUI
import Combine
import CoreBluetooth

@MainActor
class NinePViewModel: ObservableObject {
    // MARK: - Properties

    @Published var client = NinePClient()

    // Connection state
    @Published var showingConnection = true
    @Published var connectionMode: ConnectionMode = .bluetooth
    @Published var l2capTransport = L2CAPTransport()
    @Published var tcpHost = "192.168.1.100"
    @Published var tcpPort = "564"
    @Published var isConnecting = false
    @Published var connectionError: String?

    // File browsing state
    @Published var currentPath = "/"
    @Published var entries: [FileEntry] = []
    @Published var isLoading = false
    @Published var selectedFile: FileEntry?
    @Published var pathComponents: [String] = []

    // Upload state
    @Published var showingDocumentPicker = false
    @Published var isUploading = false
    @Published var uploadError: String?

    private var cancellables = Set<AnyCancellable>()

    enum ConnectionMode {
        case bluetooth, network
    }

    init() {
        // Forward objectWillChange from nested ObservableObjects to this ViewModel
        l2capTransport.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        client.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    // MARK: - Connection Methods

    func connectBluetooth(_ peripheral: CBPeripheral) {
        isConnecting = true
        connectionError = nil

        Task {
            do {
                print("🔵 [ViewModel] Selecting peripheral: \(peripheral.name ?? "Unknown")")
                l2capTransport.selectPeripheral(peripheral)

                print("🔵 [ViewModel] Connecting to L2CAP transport...")
                try await l2capTransport.connect()

                print("🔵 [ViewModel] Connecting 9P client...")
                try await client.connect(transport: l2capTransport)

                print("✅ [ViewModel] Connection successful!")
                isConnecting = false
                showingConnection = false
            } catch {
                print("❌ [ViewModel] Connection failed: \(error)")
                connectionError = error.localizedDescription
                isConnecting = false
            }
        }
    }

    func connectNetwork() {
        guard let port = UInt16(tcpPort) else {
            connectionError = "Invalid port number"
            return
        }

        isConnecting = true
        connectionError = nil

        let tcpTransport = TCPTransport(host: tcpHost, port: port)

        Task {
            do {
                try await client.connect(transport: tcpTransport)
                showingConnection = false
            } catch {
                connectionError = error.localizedDescription
                isConnecting = false
            }
        }
    }

    func disconnect() {
        print("🔴 [ViewModel] Disconnecting...")

        // Disconnect the client and transport
        client.disconnect()
        l2capTransport.disconnect()

        // Reset UI state
        showingConnection = true
        isConnecting = false
        connectionError = nil

        // Reset file browsing state
        currentPath = "/"
        entries = []
        pathComponents = []
        selectedFile = nil

        print("✅ [ViewModel] Disconnected and reset")
    }

    // MARK: - File Browsing Methods

    func loadDirectory() async {
        isLoading = true

        do {
            entries = try await client.listDirectory(path: currentPath)
        } catch {
            print("Error loading directory: \(error)")
            // TODO: Show error to user
        }

        isLoading = false
    }

    func handleTap(_ entry: FileEntry) {
        if entry.isDirectory {
            navigateToDirectory(entry.name)
        } else {
            selectedFile = entry
        }
    }

    func navigateToDirectory(_ name: String) {
        currentPath = currentPath == "/" ? "/\(name)" : "\(currentPath)/\(name)"
        pathComponents.append(name)
        Task {
            await loadDirectory()
        }
    }

    func navigateToRoot() {
        currentPath = "/"
        pathComponents = []
        Task {
            await loadDirectory()
        }
    }

    func navigateTo(index: Int) {
        pathComponents = Array(pathComponents.prefix(index + 1))
        currentPath = "/" + pathComponents.joined(separator: "/")
        Task {
            await loadDirectory()
        }
    }

    // MARK: - File Operations

    func uploadFile(from url: URL) async {
        isUploading = true
        uploadError = nil

        do {
            // Try to start accessing security-scoped resource
            // DocumentPicker with asCopy:true doesn't need this, but try anyway
            let needsSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            print("📤 [Upload] Reading file from: \(url.path)")
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            let remotePath = currentPath == "/" ? "/\(filename)" : "\(currentPath)/\(filename)"

            print("📤 [Upload] Uploading \(filename) (\(data.count) bytes) to \(remotePath)")

            try await client.writeFile(path: remotePath, data: data)

            print("✅ [Upload] Upload successful!")
            // Reload directory to show the new file
            await loadDirectory()

        } catch {
            print("❌ [Upload] Failed: \(error)")
            uploadError = error.localizedDescription
        }

        isUploading = false
    }

    func readFile(_ entry: FileEntry) async throws -> Data {
        let filePath = currentPath == "/" ? "/\(entry.name)" : "\(currentPath)/\(entry.name)"
        return try await client.readFile(path: filePath)
    }

    func writeFile(path: String, data: Data) async throws {
        try await client.writeFile(path: path, data: data)
        await loadDirectory() // Refresh
    }
}
