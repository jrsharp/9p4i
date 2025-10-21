import FileProvider
import Foundation
import UniformTypeIdentifiers

@available(iOS 16.0, macOS 13.0, *)
class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    lazy var client: NinePClient = {
        let client = NinePClient()
        return client
    }()

    let domain: NSFileProviderDomain

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        print("🔌 [FileProvider] Extension initialized for domain: \(domain.displayName)")

        // Attempt to connect to the 9P server
        // TODO: Get connection info from shared UserDefaults/Keychain
        Task {
            do {
                // Example: connect via TCP (you'll need to configure this)
                // let transport = TCPTransport(host: "192.168.1.100", port: 564)
                // try await client.connect(transport: transport)
                print("🔌 [FileProvider] Client ready (connection needed)")
            } catch {
                print("❌ [FileProvider] Connection failed: \(error)")
            }
        }
    }

    func invalidate() {
        print("🔌 [FileProvider] Extension invalidated")
    }

    // MARK: - Required NSFileProviderReplicatedExtension Methods

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        print("📦 [FileProvider] item(for: \(identifier.rawValue))")

        let progress = Progress()

        // Root item
        if identifier == .rootContainer {
            let item = FileProviderItem(identifier: .rootContainer, path: "/", isDirectory: true)
            completionHandler(item, nil)
            return progress
        }

        // Decode path from identifier
        guard let path = identifier.rawValue.removingPercentEncoding else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return progress
        }

        // For now, return a basic item
        let isDirectory = !path.contains(".")
        let item = FileProviderItem(identifier: identifier, path: path, isDirectory: isDirectory)
        completionHandler(item, nil)

        return progress
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        print("📥 [FileProvider] fetchContents(for: \(itemIdentifier.rawValue))")

        let progress = Progress()

        // TODO: Implement actual file fetching from 9P server
        completionHandler(nil, nil, NSFileProviderError(.noSuchItem))

        return progress
    }

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        print("➕ [FileProvider] createItem")

        let progress = Progress()

        // TODO: Implement item creation on 9P server
        completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))

        return progress
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        print("✏️ [FileProvider] modifyItem")

        let progress = Progress()

        // TODO: Implement item modification on 9P server
        completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))

        return progress
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        print("🗑️ [FileProvider] deleteItem")

        let progress = Progress()

        // TODO: Implement item deletion on 9P server
        completionHandler(NSFileProviderError(.noSuchItem))

        return progress
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        print("📂 [FileProvider] Creating enumerator for \(containerItemIdentifier.rawValue)")

        guard client.isConnected else {
            print("❌ [FileProvider] Client not connected")
            throw NSFileProviderError(.notAuthenticated)
        }

        return FileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier, client: client)
    }
}
