import Foundation
import ServiceManagement

/// Manages the app's launch at login status using SMAppService (macOS 13+)
@MainActor
class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var statusDescription: String = "Checking..."
    private var consecutiveFailures: Int = 0
    private static let maxRetries = 3

    private init() {
        // Check current status on init
        updateStatus()
    }

    /// Updates the published status from the system (reads SMAppService off main thread)
    func updateStatus() {
        Task.detached {
            let status = SMAppService.mainApp.status
            let enabled = status == .enabled
            let description: String
            switch status {
            case .enabled:
                description = "App will start when you log in"
            case .notRegistered:
                description = "App won't start automatically"
            case .notFound:
                description = "Login item not found — open System Settings → General → Login Items to add manually"
            case .requiresApproval:
                description = "Requires approval in System Settings → General → Login Items"
            @unknown default:
                description = "Unknown status"
            }
            await MainActor.run {
                self.isEnabled = enabled
                self.statusDescription = description
            }
        }
    }

    /// Enables or disables launch at login
    /// - Parameter enabled: Whether the app should launch at login
    /// - Returns: true if the operation succeeded
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if enabled && consecutiveFailures >= Self.maxRetries {
            log("LaunchAtLogin: Skipping register attempt — failed \(consecutiveFailures) times (Operation not permitted). User should add manually via System Settings → General → Login Items.")
            statusDescription = "Could not register — open System Settings → General → Login Items to add manually"
            return false
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
                log("LaunchAtLogin: Successfully registered for launch at login")
                consecutiveFailures = 0
            } else {
                try SMAppService.mainApp.unregister()
                log("LaunchAtLogin: Successfully unregistered from launch at login")
                consecutiveFailures = 0
            }
            updateStatus()
            return true
        } catch {
            if enabled {
                consecutiveFailures += 1
            }
            log("LaunchAtLogin: Failed to \(enabled ? "register" : "unregister") (attempt \(consecutiveFailures)/\(Self.maxRetries)): \(error.localizedDescription)")
            updateStatus()
            return false
        }
    }
}
