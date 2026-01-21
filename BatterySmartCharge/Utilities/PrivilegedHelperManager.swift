import Foundation
import ServiceManagement
import Security

class PrivilegedHelperManager {
    static let shared = PrivilegedHelperManager()

    private var xpcConnection: NSXPCConnection?
    private var isHelperInstalled = false

    init() {
        checkHelperInstalled()
    }

    // MARK: - Helper Installation

    func installHelperIfNeeded(completion: @escaping (Bool, String?) -> Void) {
        if isHelperInstalled {
            completion(true, nil)
            return
        }

        installHelper(completion: completion)
    }

    private func checkHelperInstalled() {
        // Check if helper is already installed in /Library/PrivilegedHelperTools/
        let helperPath = "/Library/PrivilegedHelperTools/\(kPowerMetricsHelperID)"
        if FileManager.default.fileExists(atPath: helperPath) {
            isHelperInstalled = true
            return
        }
        isHelperInstalled = false
    }

    private func installHelper(completion: @escaping (Bool, String?) -> Void) {
        if #available(macOS 13.0, *) {
            // Use modern SMAppService API (preferred)
            installHelperModern(completion: completion)
        } else {
            // Fallback to SMJobBless for macOS 12 and earlier
            installHelperLegacy(completion: completion)
        }
    }

    @available(macOS 13.0, *)
    private func installHelperModern(completion: @escaping (Bool, String?) -> Void) {
        do {
            // SMAppService looks for the plist in the app bundle
            let service = SMAppService.daemon(plistName: "com.smartcharge.powermetrics-helper.plist")

            // Check current status
            print("[DEBUG] Helper SMAppService status: \(String(describing: service.status.rawValue))")

            switch service.status {
            case .enabled:
                print("[DEBUG] Helper already enabled via SMAppService")
                isHelperInstalled = true
                completion(true, nil)
                return
            case .requiresApproval:
                print("[DEBUG] Helper requires approval in System Settings")
                completion(false, "Helper requires approval in System Settings > General > Login Items")
                return
            default:
                print("[DEBUG] Attempting to register helper...")
            }

            // Register the service - this will prompt for authorization
            try service.register()
            isHelperInstalled = true
            print("[DEBUG] Helper registered successfully with SMAppService")
            completion(true, nil)

        } catch {
            print("[DEBUG] SMAppService registration failed: \(error)")
            // Fallback to manual install script approach
            completion(false, "Please run: sudo ./install_helper.sh")
        }
    }

    private func installHelperLegacy(completion: @escaping (Bool, String?) -> Void) {
        // Request authorization
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authRef)

        guard status == errAuthorizationSuccess, let auth = authRef else {
            completion(false, "Failed to create authorization: \(status)")
            return
        }

        defer { AuthorizationFree(auth, []) }

        // Use withUnsafeMutablePointer to properly handle the AuthorizationItem
        let rightName = kSMRightBlessPrivilegedHelper

        var authStatus: OSStatus = errAuthorizationDenied

        rightName.withCString { cString in
            var authItem = AuthorizationItem(
                name: cString,
                valueLength: 0,
                value: nil,
                flags: 0
            )

            withUnsafeMutablePointer(to: &authItem) { itemPtr in
                var authRights = AuthorizationRights(count: 1, items: itemPtr)

                let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]

                authStatus = AuthorizationCopyRights(
                    auth,
                    &authRights,
                    nil,
                    flags,
                    nil
                )
            }
        }

        guard authStatus == errAuthorizationSuccess else {
            completion(false, "Authorization failed: \(authStatus)")
            return
        }

        // Install the helper using SMJobBless
        var error: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            kPowerMetricsHelperID as CFString,
            auth,
            &error
        )

        if success {
            isHelperInstalled = true
            completion(true, nil)
        } else {
            if let cfError = error?.takeRetainedValue() {
                let errorDesc = cfError.localizedDescription
                let domain = CFErrorGetDomain(cfError) as String
                let code = CFErrorGetCode(cfError)
                print("[DEBUG] SMJobBless failed:")
                print("[DEBUG]   Domain: \(domain)")
                print("[DEBUG]   Code: \(code)")
                print("[DEBUG]   Description: \(errorDesc)")
                completion(false, "Failed to install helper: \(errorDesc)")
            } else {
                completion(false, "Failed to install helper: Unknown error")
            }
        }
    }

    // MARK: - XPC Connection

    func getConnection() -> NSXPCConnection? {
        if let existing = xpcConnection {
            return existing
        }

        let connection = NSXPCConnection(machServiceName: kPowerMetricsHelperID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: PowerMetricsXPCProtocol.self)

        connection.invalidationHandler = { [weak self] in
            self?.xpcConnection = nil
        }

        connection.interruptionHandler = { [weak self] in
            self?.xpcConnection = nil
        }

        connection.resume()
        xpcConnection = connection

        return connection
    }

    func getPowerMetrics(completion: @escaping (Double, Double, Double, String) -> Void) {
        guard let connection = getConnection() else {
            completion(0, 0, 0, "no_connection")
            return
        }

        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            completion(0, 0, 0, "error")
        } as? PowerMetricsXPCProtocol

        proxy?.getPowerMetrics(reply: completion)
    }
}
