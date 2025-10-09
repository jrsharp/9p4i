import Foundation
import Combine

// 9P Client - manages connection and file operations
class NinePClient: ObservableObject {
    @Published var isConnected = false
    @Published var error: String?
    @Published var currentPath = "/"

    private var transport: NinePTransport?
    private var nextTag: UInt16 = 1
    private var nextFid: UInt32 = 1
    private var rootFid: UInt32 = 0
    private var msize: UInt32 = 8192
    private var pendingRequests: [UInt16: (NinePMessage) -> Void] = [:]

    // MARK: - Connection

    func connect(transport: NinePTransport) async throws {
        self.transport = transport
        transport.delegate = self

        try await transport.connect()
        try await version()
        try await attach()

        await MainActor.run {
            isConnected = true
        }
    }

    func disconnect() {
        transport?.disconnect()
        transport = nil
        pendingRequests.removeAll()
        isConnected = false
    }

    // MARK: - 9P Protocol Operations

    private func version() async throws {
        print("🟢 [9P Client] Starting version negotiation...")
        let tag: UInt16 = 0xFFFF  // NOTAG - some servers use this for version
        let msg = NinePMessageBuilder.buildVersion(tag: tag, msize: 8192, version: "9P2000")

        print("🟢 [9P Client] Sending T-version (tag=\(tag), msize=8192)")
        let response = try await sendRequest(msg, tag: tag)

        print("🟢 [9P Client] Got response: \(response.type.name)")
        guard response.type == .rversion else {
            throw NinePError.protocolError("Expected R-version, got \(response.type.name)")
        }

        if let (serverMsize, version) = response.versionInfo {
            msize = min(8192, serverMsize)
            print("🟢 [9P Client] Server msize=\(serverMsize), version=\(version), using msize=\(msize)")
            guard version == "9P2000" else {
                throw NinePError.protocolError("Unsupported version: \(version)")
            }
        }
        print("✅ [9P Client] Version negotiation complete")
    }

    private func attach() async throws {
        print("🟢 [9P Client] Starting attach...")
        rootFid = allocateFid()
        let tag = allocateTag()
        let msg = NinePMessageBuilder.buildAttach(
            tag: tag,
            fid: rootFid,
            afid: 0xFFFFFFFF,
            uname: "user",
            aname: ""
        )

        print("🟢 [9P Client] Sending T-attach (tag=\(tag), fid=\(rootFid))")
        let response = try await sendRequest(msg, tag: tag)

        print("🟢 [9P Client] Got response: \(response.type.name)")
        guard response.type == .rattach else {
            if response.type == .rerror, let error = response.errorString {
                print("❌ [9P Client] Attach failed: \(error)")
                throw NinePError.serverError(error)
            }
            throw NinePError.protocolError("Expected R-attach, got \(response.type.name)")
        }
        print("✅ [9P Client] Attach complete")
    }

    func listDirectory(path: String) async throws -> [FileEntry] {
        print("📁 [ListDir] Starting for path=\"\(path)\"")

        // Walk to the directory
        let dirFid = try await walkPath(path)
        print("📁 [ListDir] Got dirFid=\(dirFid)")

        defer {
            // Only clunk if it's not the root FID - root stays alive for session
            if dirFid != rootFid {
                Task {
                    print("📁 [ListDir] Clunking dirFid=\(dirFid)")
                    try? await clunk(fid: dirFid)
                }
            } else {
                print("📁 [ListDir] NOT clunking rootFid=\(dirFid) (keeping alive)")
            }
        }

        // Open directory for reading
        try await open(fid: dirFid, mode: 0) // OREAD

        // Read directory entries
        var entries: [FileEntry] = []
        var offset: UInt64 = 0

        while true {
            let data = try await read(fid: dirFid, offset: offset, count: UInt32(msize - 24))

            if data.isEmpty {
                break
            }

            // Parse directory entries (stat structures)
            var remaining = data
            while remaining.count > 2 {
                guard let entry = parseDirectoryEntry(&remaining) else {
                    break
                }
                entries.append(entry)
            }

            offset += UInt64(data.count)
        }

        print("📁 [ListDir] Done, got \(entries.count) entries")
        return entries
    }

    func readFile(path: String) async throws -> Data {
        print("📄 [ReadFile] Starting for path=\"\(path)\"")

        let fileFid = try await walkPath(path)
        print("📄 [ReadFile] Got fileFid=\(fileFid)")

        defer {
            // Only clunk if it's not the root FID
            if fileFid != rootFid {
                Task {
                    print("📄 [ReadFile] Clunking fileFid=\(fileFid)")
                    try? await clunk(fid: fileFid)
                }
            } else {
                print("📄 [ReadFile] NOT clunking rootFid=\(fileFid)")
            }
        }

        try await open(fid: fileFid, mode: 0) // OREAD

        var fileData = Data()
        var offset: UInt64 = 0
        let chunkSize = UInt32(msize - 24) // Leave room for headers

        while true {
            let chunk = try await read(fid: fileFid, offset: offset, count: chunkSize)

            if chunk.isEmpty {
                break
            }

            fileData.append(chunk)
            offset += UInt64(chunk.count)

            if chunk.count < chunkSize {
                break // End of file
            }
        }

        print("📄 [ReadFile] Done, got \(fileData.count) total bytes")
        return fileData
    }

    private func walkPath(_ path: String) async throws -> UInt32 {
        let components = path.split(separator: "/").map(String.init)

        print("🚶 [Walk] path=\"\(path)\", components=\(components)")

        if components.isEmpty {
            print("🚶 [Walk] empty path, returning rootFid=\(rootFid)")
            return rootFid
        }

        let newFid = allocateFid()
        let tag = allocateTag()
        print("🚶 [Walk] allocated newFid=\(newFid), tag=\(tag), walking from rootFid=\(rootFid)")

        let msg = NinePMessageBuilder.buildWalk(
            tag: tag,
            fid: rootFid,
            newFid: newFid,
            wnames: components
        )

        print("🚶 [Walk] sending TWALK...")
        let response = try await sendRequest(msg, tag: tag)

        print("🚶 [Walk] got response: \(response.type.name)")

        guard response.type == .rwalk else {
            if response.type == .rerror, let error = response.errorString {
                print("❌ [Walk] failed: \(error)")
                throw NinePError.serverError(error)
            }
            print("❌ [Walk] unexpected response type")
            throw NinePError.protocolError("Expected R-walk")
        }

        print("✅ [Walk] success, returning newFid=\(newFid)")
        return newFid
    }

    private func open(fid: UInt32, mode: UInt8) async throws {
        let tag = allocateTag()
        print("📂 [Open] fid=\(fid), mode=\(mode), tag=\(tag)")

        let msg = NinePMessageBuilder.buildOpen(tag: tag, fid: fid, mode: mode)

        let response = try await sendRequest(msg, tag: tag)

        guard response.type == .ropen else {
            if response.type == .rerror, let error = response.errorString {
                print("❌ [Open] failed: \(error)")
                throw NinePError.serverError(error)
            }
            throw NinePError.protocolError("Expected R-open")
        }

        print("✅ [Open] success")
    }

    private func read(fid: UInt32, offset: UInt64, count: UInt32) async throws -> Data {
        let tag = allocateTag()
        print("📖 [Read] fid=\(fid), offset=\(offset), count=\(count), tag=\(tag)")

        let msg = NinePMessageBuilder.buildRead(tag: tag, fid: fid, offset: offset, count: count)

        let response = try await sendRequest(msg, tag: tag)

        guard response.type == .rread else {
            if response.type == .rerror, let error = response.errorString {
                print("❌ [Read] failed: \(error)")
                throw NinePError.serverError(error)
            }
            throw NinePError.protocolError("Expected R-read")
        }

        let data = response.readData ?? Data()
        print("✅ [Read] got \(data.count) bytes")
        return data
    }

    private func clunk(fid: UInt32) async throws {
        let tag = allocateTag()
        let msg = NinePMessageBuilder.buildClunk(tag: tag, fid: fid)

        let response = try await sendRequest(msg, tag: tag)

        guard response.type == .rclunk else {
            if response.type == .rerror, let error = response.errorString {
                throw NinePError.serverError(error)
            }
            throw NinePError.protocolError("Expected R-clunk")
        }
    }

    // MARK: - Request/Response Handling

    private func sendRequest(_ data: Data, tag: UInt16) async throws -> NinePMessage {
        guard let transport = transport else {
            throw NinePError.notConnected
        }

        print("🟦 [9P Client] Sending request with tag=\(tag)")

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[tag] = { response in
                print("🟦 [9P Client] Got response for tag=\(tag): \(response.type.name)")
                continuation.resume(returning: response)
            }

            print("🟦 [9P Client] Registered handler for tag=\(tag), sending...")
            transport.send(data: data)

            // Timeout after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if self.pendingRequests.removeValue(forKey: tag) != nil {
                    print("⏰ [9P Client] Request tag=\(tag) timed out after 30s")
                    continuation.resume(throwing: NinePError.timeout)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func allocateTag() -> UInt16 {
        defer { nextTag = nextTag &+ 1 }
        return nextTag
    }

    private func allocateFid() -> UInt32 {
        defer { nextFid = nextFid &+ 1 }
        return nextFid
    }

    private func parseDirectoryEntry(_ data: inout Data) -> FileEntry? {
        guard data.count >= 2 else { return nil }

        let size = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt16.self) }
        guard data.count >= Int(size) + 2 else { return nil }

        let entryData = data.prefix(Int(size) + 2)
        data = data.dropFirst(Int(size) + 2)

        return FileEntry.parse(from: entryData)
    }
}

// MARK: - NinePTransportDelegate

extension NinePClient: NinePTransportDelegate {
    func transport(_ transport: NinePTransport, didReceive message: NinePMessage) {
        print("🟦 [9P Client] Received message: \(message.type.name) tag=\(message.tag)")
        print("🟦 [9P Client] Pending requests: \(pendingRequests.keys.sorted())")

        if let handler = pendingRequests.removeValue(forKey: message.tag) {
            print("🟦 [9P Client] Found handler for tag=\(message.tag), calling it")
            handler(message)
        } else {
            print("⚠️ [9P Client] No handler found for tag=\(message.tag)!")
        }
    }

    func transport(_ transport: NinePTransport, didDisconnectWithError error: Error?) {
        print("🔴 [9P Client] Transport disconnected, error: \(error?.localizedDescription ?? "none")")
        DispatchQueue.main.async {
            self.isConnected = false
            if let error = error {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Supporting Types

struct FileEntry: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let size: UInt64
    let mode: UInt32

    static func parse(from data: Data) -> FileEntry? {
        guard data.count >= 61 else {
            print("⚠️ FileEntry.parse: data too small (\(data.count) bytes)")
            return nil
        }

        // Ensure contiguous data
        let contiguousData = Data(data)

        // Stat structure parsing (simplified)
        // Full stat: size[2] type[2] dev[4] qid[13] mode[4] atime[4] mtime[4] length[8] name[s] uid[s] gid[s] muid[s]

        let mode = contiguousData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 21, as: UInt32.self) }
        let length = contiguousData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 33, as: UInt64.self) }

        // Parse name (string at offset 41)
        guard contiguousData.count > 43 else { return nil }
        let nameLen = contiguousData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 41, as: UInt16.self) }

        print("📊 FileEntry.parse: nameLen=\(nameLen), data.count=\(contiguousData.count)")

        guard nameLen <= 256 else {
            print("⚠️ FileEntry.parse: unreasonable name length \(nameLen)")
            return nil
        }

        guard contiguousData.count >= 43 + Int(nameLen) else {
            print("⚠️ FileEntry.parse: not enough data for name (need \(43 + Int(nameLen)), have \(contiguousData.count))")
            return nil
        }

        let startIndex = contiguousData.startIndex.advanced(by: 43)
        let endIndex = startIndex.advanced(by: Int(nameLen))
        guard endIndex <= contiguousData.endIndex else {
            print("⚠️ FileEntry.parse: index out of range")
            return nil
        }

        let nameData = contiguousData[startIndex..<endIndex]
        guard let name = String(data: nameData, encoding: .utf8) else {
            print("⚠️ FileEntry.parse: name not valid UTF-8")
            return nil
        }

        let isDirectory = (mode & 0x80000000) != 0 // DMDIR

        print("✅ FileEntry.parse: name=\"\(name)\", isDir=\(isDirectory), size=\(length)")

        return FileEntry(name: name, isDirectory: isDirectory, size: length, mode: mode)
    }

    var icon: String {
        isDirectory ? "folder.fill" : "doc.text.fill"
    }

    var sizeString: String {
        if isDirectory {
            return ""
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

enum NinePError: LocalizedError {
    case notConnected
    case timeout
    case protocolError(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .timeout:
            return "Request timeout"
        case .protocolError(let msg):
            return "Protocol error: \(msg)"
        case .serverError(let msg):
            return "Server error: \(msg)"
        }
    }
}

// MARK: - Transport Protocol

protocol NinePTransportDelegate: AnyObject {
    func transport(_ transport: NinePTransport, didReceive message: NinePMessage)
    func transport(_ transport: NinePTransport, didDisconnectWithError error: Error?)
}

protocol NinePTransport: AnyObject {
    var delegate: NinePTransportDelegate? { get set }

    func connect() async throws
    func disconnect()
    func send(data: Data)
}
