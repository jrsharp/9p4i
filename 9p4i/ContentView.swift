import SwiftUI
import CoreBluetooth
import UniformTypeIdentifiers

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var viewModel = NinePViewModel()

    var body: some View {
        Group {
            if viewModel.showingConnection {
                ConnectionView(viewModel: viewModel)
            } else {
                FileBrowserView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Connection View

struct ConnectionView: View {
    @ObservedObject var viewModel: NinePViewModel

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
                Picker("Connection", selection: $viewModel.connectionMode) {
                    Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                        .tag(NinePViewModel.ConnectionMode.bluetooth)
                    Label("Network", systemImage: "network")
                        .tag(NinePViewModel.ConnectionMode.network)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

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
            }
            .navigationBarHidden(true)
        }
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
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.l2capTransport.isScanning ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)

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
                            }
                        }
                    }
                    .disabled(viewModel.isConnecting)
                }
                .frame(height: 300)
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
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Port")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("564", text: $viewModel.tcpPort)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .autocapitalization(.none)
            }

            Button(action: { viewModel.connectNetwork() }) {
                HStack {
                    if viewModel.isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "network")
                    }
                    Text(viewModel.isConnecting ? "Connecting..." : "Connect")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.isConnecting)
        }
        .padding()
    }
}

// MARK: - File Browser View

struct FileBrowserView: View {
    @ObservedObject var viewModel: NinePViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Path breadcrumb
                if !viewModel.pathComponents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Button(action: { viewModel.navigateToRoot() }) {
                                Image(systemName: "house.fill")
                                    .foregroundColor(.blue)
                            }

                            ForEach(viewModel.pathComponents.indices, id: \.self) { index in
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button(action: { viewModel.navigateTo(index: index) }) {
                                    Text(viewModel.pathComponents[index])
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGray6))
                }

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
                    }
                }
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { viewModel.disconnect() }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        print("📤 [UI] Upload button tapped")
                        viewModel.showingDocumentPicker = true
                        print("📤 [UI] showingDocumentPicker set to true")
                    }) {
                        Label("Upload", systemImage: "arrow.up.doc")
                    }
                    .disabled(viewModel.isUploading)
                }
                #endif
            }
            .sheet(item: $viewModel.selectedFile) { file in
                FileViewerView(file: file, viewModel: viewModel)
            }
            #if os(iOS)
            .sheet(isPresented: $viewModel.showingDocumentPicker) {
                print("📤 [UI] DocumentPicker sheet appearing")
                return DocumentPicker { url in
                    print("📤 [UI] File selected: \(url.lastPathComponent)")
                    Task {
                        await viewModel.uploadFile(from: url)
                    }
                }
            }
            #endif
            .alert("Upload Error", isPresented: .constant(viewModel.uploadError != nil), actions: {
                Button("OK") { viewModel.uploadError = nil }
            }, message: {
                if let error = viewModel.uploadError {
                    Text(error)
                }
            })
            .overlay {
                if viewModel.isUploading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Uploading...")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .padding(30)
                        .background(Color(.systemGray6))
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

// MARK: - File Viewer View

struct FileViewerView: View {
    let file: FileEntry
    @ObservedObject var viewModel: NinePViewModel

    @State private var content: String = ""
    @State private var editedContent: String = ""
    @State private var fileData: Data?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingShareSheet = false
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
                    VStack(spacing: 0) {
                        // Content area
                        if isEditMode {
                            TextEditor(text: $editedContent)
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            ScrollView {
                                Text(content)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                        }

                        // Status bar for edit mode
                        if isEditMode {
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
                            .background(Color(.systemGray6))
                        }
                    }
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditMode {
                        Button("Cancel") {
                            if isModified {
                                showingDiscardAlert = true
                            } else {
                                isEditMode = false
                            }
                        }
                    } else {
                        #if os(iOS)
                        if fileData != nil {
                            Button(action: { showingShareSheet = true }) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        #endif
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditMode {
                        Button(action: { Task { await saveFile() } }) {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(!isModified || isSaving)
                    } else if !isLoading && error == nil {
                        Menu {
                            Button(action: { enterEditMode() }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(action: { dismiss() }) {
                                Label("Done", systemImage: "xmark")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingShareSheet) {
                if let data = fileData {
                    ShareSheet(items: [createTemporaryFile(data: data, filename: file.name)])
                }
            }
            #endif
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
        }
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

    private func createTemporaryFile(data: Data, filename: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        try? data.write(to: fileURL)
        return fileURL
    }
}

// MARK: - iOS-Only Helper Views

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .text, .image, .pdf], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
#endif

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
