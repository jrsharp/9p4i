import FileProvider
import Foundation

@available(iOS 16.0, *)
class FileProviderDomainManager {

    static let shared = FileProviderDomainManager()

    private let domainIdentifier = "com.9p4i.fileprovider"
    private let domainDisplayName = "9P Server"

    private init() {}

    /// Register the File Provider domain
    func registerDomain() async throws {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: domainIdentifier),
            displayName: domainDisplayName
        )

        do {
            try await NSFileProviderManager.add(domain)
            print("✅ [FileProvider] Domain registered: \(domainDisplayName)")
        } catch let error as NSError {
            // Domain might already be registered
            if error.code == NSFileProviderError.providerDomainAlreadyExists.rawValue {
                print("ℹ️ [FileProvider] Domain already registered")
            } else {
                throw error
            }
        }
    }

    /// Remove the File Provider domain
    func removeDomain() async throws {
        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: self.domainIdentifier)
        try await NSFileProviderManager.remove(domainIdentifier)
        print("🗑️ [FileProvider] Domain removed")
    }

    /// Get the manager for our domain
    func getManager() -> NSFileProviderManager? {
        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: self.domainIdentifier)
        return NSFileProviderManager(for: domainIdentifier)
    }
}
