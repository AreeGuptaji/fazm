import Foundation

/// On macOS 26+ (Tahoe), Code Signing Monitor (CSM level 2) kills JIT-entitled
/// binaries launched from within a signed app bundle's sealed Resources directory.
/// This helper copies the bundled node binary to a temp location outside the seal.
enum NodeBinaryHelper {
    private static var cachedPath: String?

    /// Returns a path to the node binary that can be safely executed.
    /// If the source path is inside the app bundle, copies it to /tmp first.
    static func externalNodePath(from bundledPath: String) -> String {
        if let cached = cachedPath,
           FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }

        let tmpNode = NSTemporaryDirectory() + "fazm-node"
        do {
            if FileManager.default.fileExists(atPath: tmpNode) {
                try FileManager.default.removeItem(atPath: tmpNode)
            }
            try FileManager.default.copyItem(atPath: bundledPath, toPath: tmpNode)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpNode)
            cachedPath = tmpNode
            log("NodeBinaryHelper: Copied bundled node to \(tmpNode) for CSM compatibility")
            return tmpNode
        } catch {
            log("NodeBinaryHelper: Failed to copy node to temp dir (\(error)), using bundled path")
            return bundledPath
        }
    }
}
