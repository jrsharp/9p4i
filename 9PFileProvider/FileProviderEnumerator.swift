import FileProvider
import Foundation

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

    let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    let client: NinePClient

    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier, client: NinePClient) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        self.client = client
        super.init()
        print("📂 [FileProviderEnumerator] Created for \(enumeratedItemIdentifier.rawValue)")
    }

    func invalidate() {
        print("📂 [FileProviderEnumerator] Invalidated")
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        print("📂 [FileProviderEnumerator] enumerateItems for \(enumeratedItemIdentifier.rawValue)")

        Task {
            do {
                // Get the path from identifier
                let path: String
                if enumeratedItemIdentifier == .rootContainer {
                    path = "/"
                } else {
                    path = enumeratedItemIdentifier.rawValue.removingPercentEncoding ?? "/"
                }

                print("📂 [FileProviderEnumerator] Listing directory: \(path)")

                // List directory contents via 9P
                let entries = try await client.listDirectory(path: path)

                print("📂 [FileProviderEnumerator] Got \(entries.count) entries")

                // Convert to FileProviderItems
                let items = entries.map { FileProviderItem(from: $0, parentPath: path) }

                // Report items to observer
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)

            } catch {
                print("❌ [FileProviderEnumerator] Failed: \(error)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        print("📂 [FileProviderEnumerator] enumerateChanges from anchor")

        // For now, just tell Files.app to re-enumerate everything
        observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(Date().description.data(using: .utf8)!), moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        // Return current timestamp as anchor
        let anchor = NSFileProviderSyncAnchor(Date().description.data(using: .utf8)!)
        completionHandler(anchor)
    }
}
