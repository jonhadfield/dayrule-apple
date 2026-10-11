import Foundation

#if os(iOS)
import UIKit
#endif

/// Apply Data Protection to on-device ciphertext files (PLAN §12).
enum FileProtection {
    /// Complete until first user authentication (or stronger). Ciphertext may
    /// still appear in device backups; wrap keys are Keychain `ThisDeviceOnly`
    /// and never leave the device.
    static func protectCiphertextFile(at url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #elseif os(macOS)
        // macOS has no equivalent Data Protection class; App Sandbox + Keychain
        // ThisDeviceOnly cover the wrap key. Ciphertext stays in Application Support.
        _ = url
        #endif
    }
}
