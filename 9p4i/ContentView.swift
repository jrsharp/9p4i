import SwiftUI

struct ContentView: View {
    @StateObject private var client = NinePClient()
    @State private var showingConnection = true

    var body: some View {
        Group {
            if showingConnection {
                ConnectionView(client: client, showingConnection: $showingConnection)
            } else {
                FileBrowserView(client: client, showingConnection: $showingConnection)
            }
        }
    }
}

// MARK: - Connection View

struct ConnectionView: View {
    @ObservedObject var client: NinePClient
    @Binding var showingConnection: Bool

    @State private var connectionMode: ConnectionMode = .bluetooth
    @StateObject private var l2capTransport = L2CAPTransport()
    @State private var tcpHost = "192.168.1.100"
    @State private var tcpPort = "564"
    @State private var isConnecting = false
    @State private var errorMessage: String?

    enum ConnectionMode {
        case bluetooth, network
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // App title
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    Text("9P File Browser")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Browse files on embedded devices")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                Spacer()

                // Connection mode picker
                Picker("Connection", selection: $connectionMode) {
                    Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                        .tag(ConnectionMode.bluetooth)
                    Label("Network", systemImage: "network")
                        .tag(ConnectionMode.network)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Connection details
                if connectionMode == .bluetooth {
                    bluetoothView
                } else {
                    networkView
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }

                Spacer()
            }
            .navigationBarHidden(true)
        }
    }

    private var bluetoothView: some View {
        VStack(spacing: 20) {
            if l2capTransport.discoveredPeripherals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text(l2capTransport.isScanning ? "Scanning..." : "No devices found")
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
            } else {
                List(l2capTransport.discoveredPeripherals, id: \.identifier) { peripheral in
                    Button(action: { connectBluetooth(peripheral) }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(peripheral.name ?? "Unknown Device")
                                    .font(.headline)
                                Text(peripheral.identifier.uuidString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if isConnecting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isConnecting)
                }
                .frame(height: 200)
                .listStyle(.plain)
            }

            Button(action: {
                if l2capTransport.isScanning {
                    l2capTransport.stopScanning()
                } else {
                    l2capTransport.startScanning()
                }
            }) {
                Label(
                    l2capTransport.isScanning ? "Stop Scanning" : "Scan for Devices",
                    systemImage: l2capTransport.isScanning ? "stop.circle.fill" : "magnifyingglass"
                )
                .frame(maxWidth: .infinity)
                .padding()
                .background(l2capTransport.isScanning ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .disabled(isConnecting)
        }
    }

    private var networkView: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Server Address")
                    .font(.headline)

                HStack {
                    TextField("IP Address", text: $tcpHost)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .autocapitalization(.none)

                    Text(":")
                        .foregroundColor(.secondary)

                    TextField("Port", text: $tcpPort)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                }
            }
            .padding(.horizontal)

            Button(action: connectNetwork) {
                if isConnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Label("Connect", systemImage: "link")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal)
            .disabled(isConnecting)
        }
    }

    private func connectBluetooth(_ peripheral: CBPeripheral) {
        isConnecting = true
        errorMessage = nil

        l2capTransport.selectPeripheral(peripheral)

        Task {
            do {
                try await client.connect(transport: l2capTransport)
                await MainActor.run {
                    showingConnection = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }

    private func connectNetwork() {
        guard let port = UInt16(tcpPort) else {
            errorMessage = "Invalid port number"
            return
        }

        isConnecting = true
        errorMessage = nil

        let tcpTransport = TCPTransport(host: tcpHost, port: port)

        Task {
            do {
                try await client.connect(transport: tcpTransport)
                await MainActor.run {
                    showingConnection = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }
}

// MARK: - File Browser View

struct FileBrowserView: View {
    @ObservedObject var client: NinePClient
    @Binding var showingConnection: Bool

    @State private var currentPath = "/"
    @State private var entries: [FileEntry] = []
    @State private var isLoading = false
    @State private var selectedFile: FileEntry?
    @State private var pathComponents: [String] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Path breadcrumb
                if !pathComponents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Button(action: { navigateToRoot() }) {
                                Image(systemName: "house.fill")
                                    .foregroundColor(.blue)
                            }

                            ForEach(pathComponents.indices, id: \.self) { index in
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button(action: { navigateTo(index: index) }) {
                                    Text(pathComponents[index])
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGray6))
                }

                // File list
                if isLoading {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
                } else if entries.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Empty directory")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List(entries) { entry in
                        Button(action: { handleTap(entry) }) {
                            HStack {
                                Image(systemName: entry.icon)
                                    .foregroundColor(entry.isDirectory ? .blue : .primary)
                                    .frame(width: 24)

                                Text(entry.name)
                                    .font(.body)

                                Spacer()

                                if !entry.isDirectory {
                                    Text(entry.sizeString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if entry.isDirectory {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingConnection = true }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            }
            .sheet(item: $selectedFile) { file in
                FileViewerView(file: file, client: client, currentPath: currentPath)
            }
            .task {
                await loadDirectory()
            }
        }
    }

    private func loadDirectory() async {
        isLoading = true

        do {
            entries = try await client.listDirectory(path: currentPath)
        } catch {
            print("Error loading directory: \(error)")
        }

        isLoading = false
    }

    private func handleTap(_ entry: FileEntry) {
        if entry.isDirectory {
            currentPath = currentPath == "/" ? "/\(entry.name)" : "\(currentPath)/\(entry.name)"
            pathComponents.append(entry.name)
            Task {
                await loadDirectory()
            }
        } else {
            selectedFile = entry
        }
    }

    private func navigateToRoot() {
        currentPath = "/"
        pathComponents = []
        Task {
            await loadDirectory()
        }
    }

    private func navigateTo(index: Int) {
        pathComponents = Array(pathComponents.prefix(index + 1))
        currentPath = "/" + pathComponents.joined(separator: "/")
        Task {
            await loadDirectory()
        }
    }
}

// MARK: - File Viewer View

struct FileViewerView: View {
    let file: FileEntry
    @ObservedObject var client: NinePClient
    let currentPath: String

    @State private var content: String = ""
    @State private var isLoading = true
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading file...")
                } else if let error = error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadFile()
            }
        }
    }

    private func loadFile() async {
        do {
            let filePath = currentPath == "/" ? "/\(file.name)" : "\(currentPath)/\(file.name)"
            print("📄 [FileViewer] Loading file at path: \(filePath)")
            let data = try await client.readFile(path: filePath)

            if let text = String(data: data, encoding: .utf8) {
                content = text
            } else {
                error = "File is not valid UTF-8 text"
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

import CoreBluetooth

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
