import Foundation

nonisolated
struct VMBundlePath: Codable, Hashable, Sendable {
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
    
    static let `default` = VMBundlePath(containerURL: FileManager.default.homeDirectoryForCurrentUser, bundleName: "VM")
    private static let `extension` = "bundle"
}

enum BundleComponent: String, CaseIterable {
    case bundle = "Bundle Directory"
    case diskImage = "Disk Image"
    case auxiliaryStorage = "Auxiliary Storage"
    case hardwareModel = "Hardware Model"
    case machineIdentifier = "Machine Identifier"
    case metadata = "Metadata"
    
    func path(in bundlePath: VMBundlePath) -> URL {
        switch self {
        case .bundle:
            return bundlePath.url
        case .diskImage:
            return bundlePath.diskImageURL
        case .auxiliaryStorage:
            return bundlePath.auxiliaryStorageURL
        case .hardwareModel:
            return bundlePath.hardwareModelURL
        case .machineIdentifier:
            return bundlePath.machineIdentifierURL
        case .metadata:
            return bundlePath.metaDataURL
        }
    }
}
