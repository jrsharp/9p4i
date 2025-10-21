//
//  _p4mApp.swift
//  9p4m
//
//  Created by Jon Sharp on 10/20/25.
//

import SwiftUI
import FileProvider

import Foundation

func logToFile(_ message: String) {
    // Use NSLog which writes to the system log (Console.app)
    NSLog("%@", message)
}

@main
struct NineP4mApp: App {
    @State private var fileProviderRegistered = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    logToFile("🚀 [App] ContentView appeared")
                    // Register File Provider domain for Finder integration
                    if #available(macOS 13.0, *) {
                        logToFile("✅ [App] macOS 13.0+ detected, registering FileProvider")
                        Task {
                            await registerFileProvider()
                        }
                    } else {
                        logToFile("⚠️ [App] macOS version < 13.0, skipping FileProvider")
                        alertMessage = "FileProvider requires macOS 13.0+"
                        showAlert = true
                    }
                }
                .alert("FileProvider Status", isPresented: $showAlert) {
                    Button("OK") { showAlert = false }
                } message: {
                    Text(alertMessage)
                }
        }
    }

    @available(macOS 13.0, *)
    private func registerFileProvider() async {
        logToFile("🔄 [FileProvider] Starting macOS domain registration...")

        // Use a simpler domain identifier
        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: "default")
        let domain = NSFileProviderDomain(
            identifier: domainIdentifier,
            displayName: "9P Server"
        )

        logToFile("📋 [FileProvider] Using domain identifier: \(domainIdentifier.rawValue)")
        logToFile("📋 [FileProvider] Extension bundle ID should be: com.9p4i.macOS.FileProvider")

        // First, try to remove any existing domain
        do {
            try await NSFileProviderManager.remove(domain)
            logToFile("🗑️ [FileProvider] Removed existing domain")
            // Wait a bit for the system to process the removal
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
            logToFile("ℹ️ [FileProvider] No existing domain to remove (or removal failed): \(error)")
        }

        logToFile("🔄 [FileProvider] Attempting to add domain '\(domain.displayName)'...")

        do {
            try await NSFileProviderManager.add(domain)
            logToFile("✅ [FileProvider] Domain registered successfully!")
            logToFile("✅ [FileProvider] '9P Server' should now appear in Finder sidebar")
            fileProviderRegistered = true

            await MainActor.run {
                alertMessage = "✅ FileProvider registered!\nCheck Finder sidebar for '9P Server'"
                showAlert = true
            }
        } catch let error as NSError {
            logToFile("❌ [FileProvider] Domain registration error: \(error)")
            logToFile("❌ [FileProvider] Error domain: \(error.domain), code: \(error.code)")
            logToFile("❌ [FileProvider] Error details: \(error.localizedDescription)")
            if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                logToFile("❌ [FileProvider] Underlying error: \(underlyingError)")
            }

            await MainActor.run {
                alertMessage = "❌ FileProvider registration failed:\n\(error.localizedDescription)\nError code: \(error.code)"
                showAlert = true
            }
        }
    }
}
