import SwiftUI
import FileProvider

@main
struct NinePForIOSApp: App {
    @State private var showingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

                if showingSplash {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // Register File Provider domain on first appear
                if #available(iOS 16.0, *) {
                    Task {
                        print("🔄 [FileProvider] Starting domain registration...")

                        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: "com.9p4i.fileprovider")
                        let domain = NSFileProviderDomain(
                            identifier: domainIdentifier,
                            displayName: "9P Server"
                        )

                        // First, try to remove any existing domain
                        do {
                            try await NSFileProviderManager.remove(domain)
                            print("🗑️ [FileProvider] Removed existing domain")
                            // Wait a bit for the system to process the removal
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        } catch {
                            print("ℹ️ [FileProvider] No existing domain to remove (or removal failed): \(error)")
                        }

                        print("🔄 [FileProvider] Attempting to add domain '\(domain.displayName)'...")

                        do {
                            try await NSFileProviderManager.add(domain)
                            print("✅ [FileProvider] Domain registered successfully!")
                        } catch let error as NSError {
                            print("❌ [FileProvider] Domain registration error: \(error)")
                            print("❌ [FileProvider] Error domain: \(error.domain), code: \(error.code)")
                            print("❌ [FileProvider] Error details: \(error.localizedDescription)")
                            if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                                print("❌ [FileProvider] Underlying error: \(underlyingError)")
                            }
                        }
                    }
                }

                // Show splash screen
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showingSplash = false
                    }
                }
            }
        }
    }
}
