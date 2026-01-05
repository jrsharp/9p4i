import Foundation
import Combine

// MARK: - Resource Management

/// Manages FID (File IDentifier) lifecycle with automatic cleanup
private actor FIDManager {
    private var nextFid: UInt32 = 1
    private var activeFids: Set<UInt32> = []
    private(set) var rootFid: UInt32 = 0
    
    func initializeRoot() -> UInt32 {
        rootFid = allocate()
        return rootFid
    }
    
    func allocate() -> UInt32 {
        let fid = nextFid
        nextFid = nextFid &+ 1
        activeFids.insert(fid)
        return fid
    }
    
    func release(_ fid: UInt32) {
        activeFids.remove(fid)
    }
    
    func isRoot(_ fid: UInt32) -> Bool {
        fid == rootFid
    }
    
    func activeCount() -> Int {
        activeFids.count
    }
    
    func reset() {
        activeFids.removeAll()
        nextFid = 1
        rootFid = 0
    }
}

/// Manages tag allocation for 9P messages with wraparound handling
private actor TagManager {
    private var nextTag: UInt16 = 1
    private var activeTags: Set<UInt16> = []
    private let reservedTag: UInt16 = 0xFFFF  // NOTAG
    
    func allocate() throws -> UInt16 {
        // Find next available tag, handling wraparound
        var attempts = 0
        while activeTags.contains(nextTag) || nextTag == reservedTag {
            nextTag = nextTag &+ 1
            if nextTag == 0 { nextTag = 1 }  // Skip 0 and NOTAG
            
            attempts += 1
            if attempts > 65000 {
                throw NinePError.protocolError("No available tags (too many concurrent requests)")
            }
        }
        
        let tag = nextTag
        nextTag = nextTag &+ 1
        if nextTag == 0 { nextTag = 1 }
        
        activeTags.insert(tag)
        return tag
    }
    
    func release(_ tag: UInt16) {
        activeTags.remove(tag)
    }
    
    func reset() {
        activeTags.removeAll()
        nextTag = 1
    }
}

/// Thread-safe request tracking with timeout management
private actor RequestTracker {
    private var pendingRequests: [UInt16: CheckedContinuation<NinePMessage, Error>] = [:]
    
    func register(tag: UInt16, continuation: CheckedContinuation<NinePMessage, Error>) {
        pendingRequests[tag] = continuation
    }
    
    func resolve(tag: UInt16, with message: NinePMessage) -> Bool {
        if let continuation = pendingRequests.removeValue(forKey: tag) {
            continuation.resume(returning: message)
            return true
        }
        return false
    }
    
    func cancel(tag: UInt16, with error: Error) -> Bool {
        if let continuation = pendingRequests.removeValue(forKey: tag) {
            continuation.resume(throwing: error)
            return true
        }
        return false
    }
    
    func reset() {
        // Cancel all pending requests
        for continuation in pendingRequests.values {
            continuation.resume(throwing: NinePError.notConnected)
        }
        pendingRequests.removeAll()
    }
}

// MARK: - 9P Client

// 9P Client - manages connection and file operations
class NinePClient: ObservableObject {
    @Published var isConnected = false
    @Published var error: String?
    @Published var currentPath = "/"
    @Published private(set) var username: String?

    private var transport: NinePTransport?
    private var msize: UInt32 = 8192
    
    // Resource managers (thread-safe via actors)
    private let fidManager = FIDManager()
    private let tagManager = TagManager()
    private let requestTracker = RequestTracker()

    // MARK: - Connection

    func connect(transport: NinePTransport, username: String) async throws {
        self.username = username
        self.transport = transport
        transport.delegate = self

        // Transport is already connected by the ViewModel, just do 9P handshake
        try await version()
        try await attach()

        await MainActor.run {
            isConnected = true
        }
    }

    func disconnect() {
        transport?.disconnect()
        transport = nil
        
        // Clean up all resources asynchronously
        Task {
            await requestTracker.reset()
            await tagManager.reset()
            await fidManager.reset()
            
            await MainActor.run {
                self.isConnected = false
                self.username = nil
            }
        }
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
        let rootFid = await fidManager.initializeRoot()
        let tag = try await tagManager.allocate()
        
        defer {
            Task { await tagManager.release(tag) }
        }
        
        let msg = NinePMessageBuilder.buildAttach(
            tag: tag,
            fid: rootFid,
            afid: 0xFFFFFFFF,
            uname: username ?? "guest",
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

        // Walk to the directory and automatically manage FID lifecycle
        return try await withFID { dirFid in
            print("📁 [ListDir] Got dirFid=\(dirFid)")
            
            // Walk to path
            try await walkTo(fid: dirFid, path: path)
            
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
    }

    func readFile(path: String, expectedSize: UInt64? = nil, progressHandler: ((Double) -> Void)? = nil) async throws -> Data {
        print("📄 [ReadFile] Starting for path=\"\(path)\"")

        return try await withFID { fileFid in
            print("📄 [ReadFile] Got fileFid=\(fileFid)")
            
            // Walk to file
            try await walkTo(fid: fileFid, path: path)
            
            // Open for reading
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
                
                // Report progress if handler provided
                if let expectedSize = expectedSize, let handler = progressHandler {
                    let progress = Double(offset) / Double(expectedSize)
                    await MainActor.run {
                        handler(min(progress, 1.0))
                    }
                }

                if chunk.count < chunkSize {
                    break // End of file
                }
            }

            print("📄 [ReadFile] Done, got \(fileData.count) total bytes")
            return fileData
        }
    }

    func writeFile(path: String, data: Data, progressHandler: ((Double) -> Void)? = nil) async throws {
        print("✏️ [WriteFile] Starting for path=\"\(path)\", data.count=\(data.count)")

        // Split path into directory and filename
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            throw NinePError.protocolError("Invalid file path")
        }

        let filename = components.last!
        let dirComponents = Array(components.dropLast())

        print("✏️ [WriteFile] dirComponents=\(dirComponents), filename=\"\(filename)\"")

        // Use elegant FID management for both directory and file
        try await withFID { dirFid in
            // Walk to parent directory
            try await walkTo(fid: dirFid, path: dirComponents.isEmpty ? "/" : "/" + dirComponents.joined(separator: "/"))
            print("✏️ [WriteFile] Got dirFid=\(dirFid)")

            // Try to walk to the file to check if it exists
            let fileExists = await (try? withFID { testFid in
                try await walkFrom(sourceFid: dirFid, destFid: testFid, names: [filename])
                return true
            }) ?? false

            print("✏️ [WriteFile] File exists: \(fileExists)")

            // Now create/open the file and write
            try await withFID { writeFid in
                if fileExists {
                    // File exists - walk and open with truncate
                    print("✏️ [WriteFile] File exists, opening for write")
                    try await walkFrom(sourceFid: dirFid, destFid: writeFid, names: [filename])
                    try await open(fid: writeFid, mode: 0x11) // OWRITE | OTRUNC
                } else {
                    // File doesn't exist - create it
                    print("✏️ [WriteFile] File doesn't exist, creating it")
                    // For create, we need to clone dirFid first, then create
                    try await walkFrom(sourceFid: dirFid, destFid: writeFid, names: [])
                    try await create(fid: writeFid, name: filename, perm: 0x1B4, mode: 1) // OWRITE, 0644
                }

                // Write data in chunks with progress reporting
                var offset: UInt64 = 0
                let chunkSize = Int(msize - 32) // Leave room for headers
                let totalSize = data.count

                while offset < data.count {
                    let end = min(Int(offset) + chunkSize, data.count)
                    let chunk = data[Int(offset)..<end]

                    let written = try await write(fid: writeFid, offset: offset, data: chunk)
                    guard written == chunk.count else {
                        throw NinePError.protocolError("Partial write: expected \(chunk.count), got \(written)")
                    }

                    offset += UInt64(written)
                    
                    // Report progress
                    if let handler = progressHandler {
                        let progress = Double(offset) / Double(totalSize)
                        await MainActor.run {
                            handler(progress)
                        }
                    }
                }

                print("✏️ [WriteFile] Done, wrote \(offset) total bytes")
            }
        }
    }

    // MARK: - Resource Management Helpers
    
    /// Automatically manages FID lifecycle - allocates on entry, clunks on exit
    private func withFID<T>(_ operation: (UInt32) async throws -> T) async throws -> T {
        let fid = await fidManager.allocate()
        
        do {
            let result = try await operation(fid)
            try await clunk(fid: fid)
            return result
        } catch {
            // Still try to clunk on error, but don't mask the original error
            try? await clunk(fid: fid)
            throw error
        }
    }
    
    /// Walk to a path from root, allocating a new FID
    private func walkTo(fid: UInt32, path: String) async throws {
        let components = path.split(separator: "/").map(String.init)
        
        if components.isEmpty {
            // Walking to root - just clone rootFid
            let rootFid = await fidManager.rootFid
            try await walkFrom(sourceFid: rootFid, destFid: fid, names: [])
        } else {
            let rootFid = await fidManager.rootFid
            try await walkFrom(sourceFid: rootFid, destFid: fid, names: components)
        }
    }
    
    /// Walk from one FID to another with given path components
    private func walkFrom(sourceFid: UInt32, destFid: UInt32, names: [String]) async throws {
        let tag = try await tagManager.allocate()
        defer {
            Task { await tagManager.release(tag) }
        }
        
        print("🚶 [Walk] sourceFid=\(sourceFid) -> destFid=\(destFid), names=\(names)")
        
        let msg = NinePMessageBuilder.buildWalk(
            tag: tag,
            fid: sourceFid,
            newFid: destFid,
            wnames: names
        )
        
        let response = try await sendRequest(msg, tag: tag)
        
        guard response.type == .rwalk else {
            if response.type == .rerror, let error = response.errorString {
                print("❌ [Walk] failed: \(error)")
                throw NinePError.serverError(error)
            }
            throw NinePError.protocolError("Expected R-walk")
        }
        
        print("✅ [Walk] success")
    }

    // Legacy walkPath - kept for compatibility but uses new system
    private func walkPath(_ path: String) async throws -> UInt32 {
        let fid = await fidManager.allocate()
        
        do {
            try await walkTo(fid: fid, path: path)
            return fid
        } catch {
            await fidManager.release(fid)
            throw error
        }
    }

    private func open(fid: UInt32, mode: UInt8) async throws {
        let tag = try await tagManager.allocate()
        defer {
            Task { await tagManager.release(tag) }
        }
        
        let modeString = mode == 0 ? "OREAD" : mode == 1 ? "OWRITE" : mode == 2 ? "ORDWR" : mode == 0x11 ? "OWRITE|OTRUNC" : "0x\(String(mode, radix: 16))"
        print("📂 [Open] fid=\(fid), mode=\(modeString) (0x\(String(mode, radix: 16))), tag=\(tag)")

        let msg = NinePMessageBuilder.buildOpen(tag: tag, fid: fid, mode: mode)

        let response = try await sendRequest(msg, tag: tag)

        guard response.type == .ropen else {
            if response.type == .rerror, let error = response.errorString {
                print("❌ [Open] failed: \(error)")
                throw NinePError.serverError(error)
            }
            print("❌ [Open] unexpected response: \(response.type.name)")
            throw NinePError.protocolError("Expected R-open")
        }

        print("✅ [Open] success")
    }

    private func read(fid: UInt32, offset: UInt64, count: UInt32) async throws -> Data {
        let tag = try await tagManager.allocate()
        defer {
            Task { await tagManager.release(tag) }
        }
        
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

    private func write(fid: UInt32, offset: UInt64, data: Data) async throws -> UInt32 {
        let tag = try await tagManager.allocate()
        defer {
            Task { await tagManager.release(tag) }
        }
        
        print("✏️ [Write] fid=\(fid), offset=\(offset), count=\(data.count), tag=\(tag)")

        let msg = NinePMessageBuilder.buildWrite(tag: tag, fid: fid, offset: offset, writeData: data)

        let response = try await sendRequest(msg, tag: tag)

        guard response.type == .rwrite else {
            if response.type == .rerror, let error = response.errorString {
                print("❌ [Write] failed: \(error)")
                throw NinePError.serverError(error)
            }
            throw NinePError.protocolError("Expected R-write")
        }

        let count = response.writeCount ?? 0
        print("✅ [Write] wrote \(count) bytes")
        return count
    }

    private func create(fid: UInt32, name: String, perm: UInt32, mode: UInt8) async throws {
        let tag = try await tagManager.allocate()
        defer {
            Task { await tagManager.release(tag) }
        }
        
        print("📝 [Create] fid=\(fid), name=\"\(name)\", perm=0x\(String(perm, radix: 16)), mode=\(mode), tag=\(tag)")

        let msg = NinePMessageBuilder.buildCreate(tag: tag, fid: fid, name: name, perm: perm, mode: mode)

        let response = try await sendRequest(msg, tag: tag)

        guard response.type == .rcreate else {
            if response.type == .rerror, let error = response.errorString {
                print("❌ [Create] failed: \(error)")
                throw NinePError.serverError(error)
            }
            throw NinePError.protocolError("Expected R-create")
        }

        print("✅ [Create] success")
    }

    private func clunk(fid: UInt32) async throws {
        // Check if this is the root FID - never clunk it!
        if await fidManager.isRoot(fid) {
            print("🔒 [Clunk] Skipping root FID \(fid)")
            return
        }
        
        let tag = try await tagManager.allocate()
        defer {
            Task { await tagManager.release(tag) }
        }
        
        print("👋 [Clunk] fid=\(fid), tag=\(tag)")
        
        let msg = NinePMessageBuilder.buildClunk(tag: tag, fid: fid)

        do {
            let response = try await sendRequest(msg, tag: tag)

            guard response.type == .rclunk else {
                if response.type == .rerror, let error = response.errorString {
                    throw NinePError.serverError(error)
                }
                throw NinePError.protocolError("Expected R-clunk")
            }
            
            // Release the FID from tracking
            await fidManager.release(fid)
            print("✅ [Clunk] success, released fid=\(fid)")
        } catch {
            // Even if clunk fails, release from tracking to avoid leaks
            await fidManager.release(fid)
            throw error
        }
    }

    // MARK: - Request/Response Handling

    private func sendRequest(_ data: Data, tag: UInt16) async throws -> NinePMessage {
        guard let transport = transport else {
            throw NinePError.notConnected
        }

        print("🟦 [9P Client] Sending request with tag=\(tag)")

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await requestTracker.register(tag: tag, continuation: continuation)
            }
            
            print("🟦 [9P Client] Registered handler for tag=\(tag), sending...")
            transport.send(data: data)

            // Timeout after 30 seconds
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if await requestTracker.cancel(tag: tag, with: NinePError.timeout) {
                    print("⏰ [9P Client] Request tag=\(tag) timed out after 30s")
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func parseDirectoryEntry(_ data: inout Data) -> FileEntry? {
        guard data.count >= 2 else { return nil }

        let size = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt16.self) }
        guard data.count >= Int(size) + 2 else { return nil }

        let entryData = data.prefix(Int(size) + 2)
        data = data.dropFirst(Int(size) + 2)

        return FileEntry.parse(from: entryData)
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic information about active resources
    func diagnostics() async -> ResourceDiagnostics {
        ResourceDiagnostics(
            activeFidCount: await fidManager.activeCount(),
            rootFid: await fidManager.rootFid,
            isConnected: isConnected,
            username: username
        )
    }
}

// MARK: - Diagnostics Support

struct ResourceDiagnostics: CustomStringConvertible {
    let activeFidCount: Int
    let rootFid: UInt32
    let isConnected: Bool
    let username: String?
    
    var description: String {
        """
        📊 9P Client Diagnostics:
        - Connected: \(isConnected)
        - Username: \(username ?? "none")
        - Root FID: \(rootFid)
        - Active FIDs: \(activeFidCount)
        """
    }
}

// MARK: - NinePTransportDelegate

extension NinePClient: NinePTransportDelegate {
    func transport(_ transport: NinePTransport, didReceive message: NinePMessage) {
        print("🟦 [9P Client] Received message: \(message.type.name) tag=\(message.tag)")
        
        Task {
            let handled = await requestTracker.resolve(tag: message.tag, with: message)
            if handled {
                print("🟦 [9P Client] Handler called for tag=\(message.tag)")
            } else {
                print("⚠️ [9P Client] No handler found for tag=\(message.tag)!")
            }
        }
    }

    func transport(_ transport: NinePTransport, didDisconnectWithError error: Error?) {
        print("🔴 [9P Client] Transport disconnected, error: \(error?.localizedDescription ?? "none")")
        
        Task {
            await requestTracker.reset()
        }
        
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
