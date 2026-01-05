import SwiftUI
import UniformTypeIdentifiers

/// DFU (Device Firmware Update) view for updating device firmware via 9P
struct DFUView: View {
    @ObservedObject var dfuManager: DFUManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var selectedFileName: String?
    @State private var showingRebootConfirm = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                headerView

                Divider()

                // Status section
                statusSection

                Spacer()

                // Action buttons
                actionButtons

                Spacer()
            }
            .padding()
            .navigationTitle("Firmware Update")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(dfuManager.state.isWorking)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await dfuManager.readStatus() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(dfuManager.state.isWorking)
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(dfuManager.state.isWorking)
                }

                ToolbarItem(placement: .automatic) {
                    Button(action: { Task { await dfuManager.readStatus() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(dfuManager.state.isWorking)
                }
                #endif
            }
            #if os(iOS)
            .sheet(isPresented: $showingFilePicker) {
                FirmwarePicker { url in
                    selectedFileName = url.lastPathComponent
                    Task {
                        await dfuManager.uploadFirmware(from: url)
                    }
                }
            }
            #else
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [
                    .data,
                    UTType(filenameExtension: "bin") ?? .data,
                    UTType(filenameExtension: "hex") ?? .data,
                    UTType(filenameExtension: "uf2") ?? .data,
                    UTType(filenameExtension: "dfu") ?? .data,
                ]
            ) { result in
                switch result {
                case .success(let url):
                    selectedFileName = url.lastPathComponent
                    Task {
                        await dfuManager.uploadFirmware(from: url)
                    }
                case .failure(let error):
                    print("File picker error: \(error.localizedDescription)")
                }
            }
            #endif
            .alert("Reboot Device?", isPresented: $showingRebootConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reboot") {
                    Task { await dfuManager.reboot() }
                }
            } message: {
                Text("The device will restart to apply the firmware update. Make sure the firmware has been fully uploaded.")
            }
            .task {
                await dfuManager.readStatus()
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: stateIcon)
                .font(.system(size: 48))
                .foregroundColor(stateColor)

            Text(dfuManager.state.description)
                .font(.headline)
                .foregroundColor(stateColor)
        }
    }

    private var stateIcon: String {
        switch dfuManager.state {
        case .idle: return "cpu"
        case .reading: return "magnifyingglass"
        case .erasing: return "eraser"
        case .uploading: return "arrow.up.circle"
        case .verifying: return "checkmark.shield"
        case .waitingReboot: return "arrow.clockwise.circle"
        case .rebooting: return "power"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch dfuManager.state {
        case .idle: return .primary
        case .success: return .green
        case .error: return .red
        case .waitingReboot: return .orange
        default: return .blue
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 16) {
            // Progress indicator for active operations
            if dfuManager.state.isWorking {
                VStack(spacing: 8) {
                    if dfuManager.state == .uploading {
                        ProgressView(value: dfuManager.progress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text(formatBytes(dfuManager.bytesTransferred))
                            Text("/")
                            Text(formatBytes(dfuManager.totalBytes))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                }
                .padding()
                #if os(iOS)
                .background(Color(.systemGray6))
                #else
                .background(Color(nsColor: .systemGray).opacity(0.3))
                #endif
                .cornerRadius(12)
            }

            // Current firmware info
            if let status = dfuManager.firmwareStatus {
                VStack(spacing: 12) {
                    infoRow("Device State", value: status.state)

                    if let version = status.currentVersion {
                        infoRow("Current Version", value: version)
                    }

                    infoRow("Image Confirmed", value: status.isConfirmed ? "Yes" : "No")

                    if status.bytesReceived > 0 {
                        infoRow("Bytes Received", value: formatBytes(UInt64(status.bytesReceived)))
                    }
                }
                .padding()
                #if os(iOS)
                .background(Color(.systemGray6))
                #else
                .background(Color(nsColor: .systemGray).opacity(0.3))
                #endif
                .cornerRadius(12)
            }

            // Warning if image not confirmed
            if let status = dfuManager.firmwareStatus, !status.isConfirmed {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Image not confirmed! Will revert on next reboot.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Upload firmware button
            Button(action: { showingFilePicker = true }) {
                HStack {
                    Image(systemName: "arrow.up.doc.fill")
                    Text("Select Firmware File")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(dfuManager.state.isWorking)

            // Confirm image button (if needed)
            if let status = dfuManager.firmwareStatus, !status.isConfirmed {
                Button(action: { Task { await dfuManager.confirmImage() } }) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Confirm Current Image")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(dfuManager.state.isWorking)
            }

            // Reboot button (if firmware uploaded)
            if dfuManager.state == .waitingReboot {
                Button(action: { showingRebootConfirm = true }) {
                    HStack {
                        Image(systemName: "power")
                        Text("Reboot to Apply")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }

            // Reset button (if error)
            if case .error = dfuManager.state {
                Button(action: { dfuManager.reset() }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Try Again")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    #if os(iOS)
                    .background(Color(.systemGray5))
                    #else
                    .background(Color(nsColor: .systemGray).opacity(0.5))
                    #endif
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Firmware File Picker

#if os(iOS)
struct FirmwarePicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Accept common firmware file types
        let types: [UTType] = [
            .data,                          // .bin files
            UTType(filenameExtension: "bin") ?? .data,
            UTType(filenameExtension: "hex") ?? .data,
            UTType(filenameExtension: "uf2") ?? .data,
            UTType(filenameExtension: "dfu") ?? .data,
        ]

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
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

struct DFUView_Previews: PreviewProvider {
    static var previews: some View {
        DFUView(dfuManager: DFUManager())
    }
}
