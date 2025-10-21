import SwiftUI
import CoreBluetooth
import UniformTypeIdentifiers
import AppKit

#if os(macOS)

// MARK: - Main Content View (macOS)

struct ContentView: View {
    @StateObject private var viewModel = NinePViewModel()

    var body: some View {
        Group {
            if viewModel.showingConnection {
                ConnectionView_macOS(viewModel: viewModel)
            } else {
                FileBrowserView_macOS(viewModel: viewModel)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Connection View (macOS)

struct ConnectionView_macOS: View {
    @ObservedObject var viewModel: NinePViewModel

    var body: some View {
        VStack(spacing: 30) {
            // App branding with Glenda
            VStack(spacing: 12) {
                Image("GlendaImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 150, height: 150)

                Text("9p4i")
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .foregroundColor(.primary)

                Text("Plan 9 File Browser")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            Spacer()

            // Connection mode picker
            Picker("Connection", selection: $viewModel.connectionMode) {
                Text("Bluetooth").tag(NinePViewModel.ConnectionMode.bluetooth)
                Text("Network").tag(NinePViewModel.ConnectionMode.network)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            // Connection details
            if viewModel.connectionMode == .bluetooth {
                bluetoothView
            } else {
                networkView
            }

            if let error = viewModel.connectionError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }

            Spacer()

            // Glenda footer
            Text("Powered by Glenda")
                .font(.system(size: 12, weight: .light, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bluetoothView: some View {
        VStack(spacing: 20) {
            // Scan button
            Button(action: {
                if viewModel.l2capTransport.isScanning {
                    viewModel.l2capTransport.stopScanning()
                } else {
                    viewModel.l2capTransport.startScanning()
                }
            }) {
                HStack {
                    Image(systemName: viewModel.l2capTransport.isScanning ? "stop.circle" : "antenna.radiowaves.left.and.right")
                    Text(viewModel.l2capTransport.isScanning ? "Stop Scanning" : "Start Scanning")
                }
                .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)

            if viewModel.l2capTransport.discoveredPeripherals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text(viewModel.l2capTransport.isScanning ? "Scanning..." : "No devices found")
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
            } else {
                List(viewModel.l2capTransport.discoveredPeripherals, id: \.identifier) { peripheral in
                    Button(action: { viewModel.connectBluetooth(peripheral) }) {
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
                            if viewModel.isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isConnecting)
                }
                .frame(width: 400, height: 300)
            }
        }
        .padding()
    }

    private var networkView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hostname / IP")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("192.168.1.100", text: $viewModel.tcpHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Port")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("564", text: $viewModel.tcpPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
            }

            Button(action: { viewModel.connectNetwork() }) {
                HStack {
                    if viewModel.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "network")
                    }
                    Text(viewModel.isConnecting ? "Connecting..." : "Connect")
                        .fontWeight(.semibold)
                }
                .frame(width: 280)
            }
            .disabled(viewModel.isConnecting)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - File Browser View (macOS)

struct FileBrowserView_macOS: View {
    @ObservedObject var viewModel: NinePViewModel

    var body: some View {
        NavigationSplitView {
            // Sidebar could show favorites, recent, etc.
            List {
                Label("Root", systemImage: "house.fill")
                    .onTapGesture {
                        viewModel.navigateToRoot()
                    }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                // Path breadcrumb
                if !viewModel.pathComponents.isEmpty {
                    HStack(spacing: 4) {
                        Button(action: { viewModel.navigateToRoot() }) {
                            Image(systemName: "house.fill")
                        }
                        .buttonStyle(.plain)

                        ForEach(viewModel.pathComponents.indices, id: \.self) { index in
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button(action: { viewModel.navigateTo(index: index) }) {
                                Text(viewModel.pathComponents[index])
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                }

                Divider()

                // File list
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
                } else if viewModel.entries.isEmpty {
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
                    List(viewModel.entries) { entry in
                        Button(action: { viewModel.handleTap(entry) }) {
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
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Files")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: { viewModel.disconnect() }) {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.begin { response in
                            if response == .OK, let url = panel.url {
                                Task {
                                    await viewModel.uploadFile(from: url)
                                }
                            }
                        }
                    }) {
                        Label("Upload", systemImage: "arrow.up.doc")
                    }
                    .disabled(viewModel.isUploading)
                }
            }
            .sheet(item: $viewModel.selectedFile) { file in
                FileViewerView_macOS(file: file, viewModel: viewModel)
            }
            .overlay {
                if viewModel.isUploading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Uploading...")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .padding(30)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(12)
                    }
                }
            }
            .task {
                await viewModel.loadDirectory()
            }
        }
    }
}

// MARK: - File Viewer View (macOS)

struct FileViewerView_macOS: View {
    let file: FileEntry
    @ObservedObject var viewModel: NinePViewModel

    @State private var content: String = ""
    @State private var editedContent: String = ""
    @State private var fileData: Data?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isEditMode = false
    @State private var isSaving = false
    @State private var showingDiscardAlert = false
    @Environment(\.dismiss) private var dismiss

    private var isModified: Bool {
        isEditMode && editedContent != content
    }

    private var characterCount: Int {
        editedContent.count
    }

    private var lineCount: Int {
        editedContent.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading file...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Content area
                if isEditMode {
                    TextEditor(text: $editedContent)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                } else {
                    ScrollView {
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }

                // Status bar
                if isEditMode {
                    Divider()
                    HStack {
                        Text("\(lineCount) lines")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if isModified {
                            Text("Modified")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        Text("\(characterCount) chars")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
            }
        }
        .navigationTitle(file.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isEditMode {
                    Button("Cancel") {
                        if isModified {
                            showingDiscardAlert = true
                        } else {
                            isEditMode = false
                        }
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                if isEditMode {
                    Button(action: { Task { await saveFile() } }) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!isModified || isSaving)
                } else if !isLoading && error == nil {
                    Button("Edit") {
                        enterEditMode()
                    }
                }
            }
        }
        .alert("Discard Changes?", isPresented: $showingDiscardAlert) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) {
                editedContent = content
                isEditMode = false
            }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        .interactiveDismissDisabled(isModified)
        .task {
            await loadFile()
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private func loadFile() async {
        do {
            let data = try await viewModel.readFile(file)
            fileData = data

            if let text = String(data: data, encoding: .utf8) {
                content = text
                editedContent = text
            } else {
                error = "File is not valid UTF-8 text"
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func enterEditMode() {
        editedContent = content
        isEditMode = true
    }

    private func saveFile() async {
        isSaving = true

        do {
            let filePath = viewModel.currentPath == "/" ? "/\(file.name)" : "\(viewModel.currentPath)/\(file.name)"
            let data = editedContent.data(using: .utf8) ?? Data()

            try await viewModel.writeFile(path: filePath, data: data)

            // Update the content to reflect saved state
            content = editedContent
            fileData = data
            isEditMode = false

            print("✅ [FileViewer] File saved successfully")
        } catch {
            print("❌ [FileViewer] Save failed: \(error)")
            self.error = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

#endif
