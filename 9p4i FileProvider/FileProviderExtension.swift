import FileProvider
import Foundation

class FileProviderExtension: NSFileProviderExtension {

    lazy var client: NinePClient = {
        let client = NinePClient()

        // TODO: Get connection info from shared UserDefaults/Keychain
        // For now, we'll need to connect manually
        // This is a limitation we'll need to address with proper setup

        return client
    }()

    override init() {
        super.init()
        print("🔌 [FileProvider] Extension initialized")

        // Attempt to connect to the 9P server
        // In a real implementation, you'd get these from shared preferences
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

    override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
        print("📦 [FileProvider] item(for: \(identifier.rawValue))")

        // Root item
        if identifier == .rootContainer {
            return FileProviderItem(identifier: .rootContainer, path: "/", isDirectory: true)
        }

        // Decode path from identifier
        guard let path = identifier.rawValue.removingPercentEncoding else {
            throw NSFileProviderError(.noSuchItem)
        }

        // For now, return a basic item - we'll enhance this later
        let isDirectory = !path.contains(".")
        return FileProviderItem(identifier: identifier, path: path, isDirectory: isDirectory)
    }

    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        print("📂 [FileProvider] Creating enumerator for \(containerItemIdentifier.rawValue)")

        guard client.isConnected else {
            print("❌ [FileProvider] Client not connected")
            throw NSFileProviderError(.notAuthenticated)
        }

        return FileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier, client: client)
    }

    override func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                                version requestedVersion: NSFileProviderItemVersion?,
                                request: NSFileProviderRequest,
                                completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {

        print("📥 [FileProvider] fetchContents for \(itemIdentifier.rawValue)")

        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                guard let path = itemIdentifier.rawValue.removingPercentEncoding else {
                    throw NSFileProviderError(.noSuchItem)
                }

                // Read file from 9P server
                let data = try await client.readFile(path: path)

                // Write to temporary file
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension((path as NSString).pathExtension)

                try data.write(to: tempURL)

                let item = FileProviderItem(identifier: itemIdentifier, path: path, isDirectory: false)
                item.fileSize = Int64(data.count)

                progress.completedUnitCount = 1
                completionHandler(tempURL, item, nil)

            } catch {
                print("❌ [FileProvider] fetchContents failed: \(error)")
                completionHandler(nil, nil, error)
            }
        }

        return progress
    }

    override func createItem(basedOn itemTemplate: NSFileProviderItem,
                            fields: NSFileProviderItemFields,
                            contents url: URL?,
                            options: NSFileProviderCreateItemOptions = [],
                            request: NSFileProviderRequest,
                            completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {

        print("📤 [FileProvider] createItem: \(itemTemplate.filename)")

        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                // Get parent path
                let parentPath: String
                if itemTemplate.parentItemIdentifier == .rootContainer {
                    parentPath = "/"
                } else {
                    parentPath = itemTemplate.parentItemIdentifier.rawValue.removingPercentEncoding ?? "/"
                }

                let fullPath = parentPath == "/" ? "/\(itemTemplate.filename)" : "\(parentPath)/\(itemTemplate.filename)"

                // Read contents if provided
                if let url = url {
                    let data = try Data(contentsOf: url)
                    try await client.writeFile(path: fullPath, data: data)
                }

                let newItem = FileProviderItem(
                    identifier: NSFileProviderItemIdentifier(fullPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fullPath),
                    path: fullPath,
                    isDirectory: itemTemplate.contentType == .folder
                )

                progress.completedUnitCount = 1
                completionHandler(newItem, [], false, nil)

            } catch {
                print("❌ [FileProvider] createItem failed: \(error)")
                completionHandler(nil, [], false, error)
            }
        }

        return progress
    }

    override func modifyItem(_ item: NSFileProviderItem,
                            baseVersion version: NSFileProviderItemVersion,
                            changedFields: NSFileProviderItemFields,
                            contents newContents: URL?,
                            options: NSFileProviderModifyItemOptions = [],
                            request: NSFileProviderRequest,
                            completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {

        print("✏️ [FileProvider] modifyItem: \(item.filename)")

        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                guard let path = item.itemIdentifier.rawValue.removingPercentEncoding else {
                    throw NSFileProviderError(.noSuchItem)
                }

                // Write new contents if provided
                if let url = newContents {
                    let data = try Data(contentsOf: url)
                    try await client.writeFile(path: path, data: data)
                }

                progress.completedUnitCount = 1
                completionHandler(item, [], false, nil)

            } catch {
                print("❌ [FileProvider] modifyItem failed: \(error)")
                completionHandler(nil, [], false, error)
            }
        }

        return progress
    }

    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        guard let item = try? item(for: identifier) else {
            return nil
        }

        return NSFileProviderManager.default.documentStorageURL.appendingPathComponent(identifier.rawValue, isDirectory: false)
    }

    override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
        let pathComponents = url.pathComponents
        guard pathComponents.count > 0 else {
            return .rootContainer
        }

        return NSFileProviderItemIdentifier(url.lastPathComponent)
    }
}

