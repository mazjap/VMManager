import Foundation

nonisolated
struct VmBundlePath: Codable, Hashable, Sendable {
    let url: URL
    
    var containerURL: URL {
        url.deletingLastPathComponent()
    }
    
    var bundleName: String {
        url.deletingPathExtension().lastPathComponent
    }
    
    var auxiliaryStorageURL: URL {
        url.appending(path: "AuxiliaryStorage")
    }
    
    var diskImageURL: URL {
        url.appending(path: "Disk").appendingPathExtension("img")
    }
    
    var hardwareModelURL: URL {
        url.appending(path: "HardwareModel")
    }
    
    var machineIdentifierURL: URL {
        url.appending(path: "MachineIdentifier")
    }
    
    var restoreImageURL: URL {
        url.appending(path: "RestoreImage").appendingPathExtension("ipsw")
    }
    
    var saveFileURL: URL {
        url.appending(path: "SaveFile").appendingPathExtension("vzvmsave")
    }
    
    var metaDataURL: URL {
        url.appending(path: "Metadata")
    }
    
    init(containerURL: URL, bundleName: String) {
        self.url = containerURL
            .appending(path: bundleName)
            .appendingPathExtension(Self.extension)
    }
    
    /// Throws CocoaError.fileReadUnsupportedScheme if url's last path component does not end in .bundle suffix
    init(bundleURL: URL) throws {
        guard bundleURL.pathExtension == Self.extension else { throw CocoaError(.fileReadUnsupportedScheme) }
        self.url = bundleURL
    }
    
    static let `default` = VmBundlePath(containerURL: FileManager.default.homeDirectoryForCurrentUser, bundleName: "VM")
    private static let `extension` = "bundle"
}
