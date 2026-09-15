import Foundation
import Darwin

/// Stable lock files are never removed, so all processes lock the same inode.
public final class FileLock {
    private var descriptor: Int32 = -1
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw UVError("Cannot open ownership lock: \(String(cString: strerror(errno)))") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); descriptor = -1
            throw UVError("VM or store is busy; stop it or wait for the current operation.")
        }
    }
    public func unlock() {
        if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1 }
    }
    deinit { unlock() }
}
