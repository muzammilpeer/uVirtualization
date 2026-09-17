import Foundation
import Darwin

/// Prefer APFS copy-on-write; use a regular copy only when the filesystem cannot clone.
public func copyArtifact(from source: URL, to destination: URL) throws {
    try requireRegularFile(source)
    if clonefile(source.path, destination.path, 0) == 0 { return }
    let code = errno
    guard [ENOTSUP, EXDEV, EINVAL].contains(code) else {
        throw UVError("Cannot clone artifact: \(String(cString: strerror(code)))")
    }
    try FileManager.default.copyItem(at: source, to: destination)
}
