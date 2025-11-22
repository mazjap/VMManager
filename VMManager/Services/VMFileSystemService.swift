import Foundation
import Virtualization

// MARK: - Supporting Types

enum BundleValidationResult {
    case valid
    case missing(components: [BundleComponent])
    case corrupted(component: BundleComponent, error: Error)
    case inaccessible(error: Error)
}

struct VMCreationConfiguration {
    let name: String
    let containerURL: URL
    let launchOptions: LaunchOptions
    let customIpswURL: URL? // nil means download from Apple
}

// MARK: - VMFileSystemService

class VMFileSystemService {
    private let diskUtilityClient: DiskUtilityClient
    
    init(diskUtilityClient: DiskUtilityClient = DiskUtilityClient()) {
        self.diskUtilityClient = diskUtilityClient
    }
    
    // MARK: - Bundle Management
    
    func createBundle(at path: VMBundlePath) throws(VMFileSystemError) {
        do {
            try FileManager.default.createDirectory(
                atPath: path.url.path(percentEncoded: false),
                withIntermediateDirectories: true
            )
        } catch {
            throw VMFileSystemError.bundleCreationFailed(path: path.url, underlying: error)
        }
    }
    
    func validateBundle(at path: VMBundlePath) throws(VMFileSystemError) -> BundleValidationResult {
        guard FileManager.default.fileExists(atPath: path.url.path(percentEncoded: false)) else {
            return .missing(components: [.bundle])
        }
        
        do {
            try validateSecurityAccessInternal(for: path.url)
        } catch {
            return .inaccessible(error: error)
        }
        
        var missingComponents: [BundleComponent] = []
        
        for component in BundleComponent.allCases {
            guard component != .bundle else { continue }
            
            let componentPath = component.path(in: path)
            
            if !FileManager.default.fileExists(atPath: componentPath.path(percentEncoded: false)) {
                missingComponents.append(component)
                continue
            }
            
            do {
                try validateComponentIntegrity(component: component, at: componentPath)
            } catch {
                return .corrupted(component: component, error: error)
            }
        }
        
        return missingComponents.isEmpty ? .valid : .missing(components: missingComponents)
    }
    
    func repairBundle(at path: VMBundlePath) throws(VMFileSystemError) {
        let validationResult = try validateBundle(at: path)
        
        switch validationResult {
        case .valid:
            return
        case .missing(let components):
            for component in components {
                switch component {
                case .bundle:
                    try createBundle(at: path)
                case .metadata:
                    try createMetadata(at: path.metaDataURL, options: VMConfigHelper.defaultLaunchOptions)
                case .machineIdentifier:
                    try createMachineIdentifier(at: path.machineIdentifierURL)
                case .auxiliaryStorage:
                    let hardwareModelData: Data
                    do {
                        hardwareModelData = try Data(contentsOf: path.hardwareModelURL)
                    } catch {
                        throw .accessingDataFromUrl(url: path.hardwareModelURL, underlying: error)
                    }
                    
                    guard let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareModelData) else { throw VMFileSystemError.cannotRepairCriticalComponent(.auxiliaryStorage) }
                    
                    try createAuxiliaryStorage(at: path.auxiliaryStorageURL, with: hardwareModel)
                case .hardwareModel:
                    throw VMFileSystemError.cannotRepairCriticalComponent(component)
                    // TODO: - Allow user to select restore image to pull hardware model from
//                    try createHardwareModel(at: path.hardwareModelURL, with: hardwareModel)
                case .diskImage:
                    // If the disk image is gone, then this VM is screwed. Maybe ask user if they'd like it to be recreated?
                    throw VMFileSystemError.cannotRepairCriticalComponent(component)
                }
            }
        case .corrupted(let component, let error):
            throw VMFileSystemError.cannotRepairCorruptedComponent(component, underlying: error)
        case .inaccessible(let error):
            throw VMFileSystemError.cannotRepairInaccessibleBundle(underlying: error)
        }
    }
    
    func deleteBundle(at path: VMBundlePath) throws(VMFileSystemError) {
        let accessGranted = path.url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                path.url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            try FileManager.default.removeItem(at: path.url)
        } catch {
            throw VMFileSystemError.bundleDeletionFailed(path: path.url, underlying: error)
        }
    }
    
    // MARK: - File Operations
    
    func copyRestoreImage(from sourceURL: URL, to bundlePath: VMBundlePath) async throws(VMFileSystemError) {
        let restoreImageURL = bundlePath.restoreImageURL
        
        do {
            try await Task.detached(priority: .userInitiated) {
                let ipswAccessGranted = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if ipswAccessGranted {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                
                try FileManager.default.copyItem(at: sourceURL, to: restoreImageURL)
            }.value
        } catch {
            throw VMFileSystemError.restoreImageCopyFailed(from: sourceURL, to: restoreImageURL, underlying: error)
        }
    }
    
    func createAuxiliaryFiles(at path: VMBundlePath, config: VMCreationConfiguration, hardwareModel: VZMacHardwareModel) async throws(VMFileSystemError) {
        try await createDiskImage(at: path.diskImageURL, sizeInGb: config.launchOptions.storageGb)
        try createAuxiliaryStorage(at: path.auxiliaryStorageURL, with: hardwareModel)
        try createHardwareModel(at: path.hardwareModelURL, with: hardwareModel)
        try createMachineIdentifier(at: path.machineIdentifierURL)
        try createMetadata(at: path.metaDataURL, options: config.launchOptions)
    }
    
    func updateMetadata(at path: VMBundlePath, launchOptions: LaunchOptions) throws(VMFileSystemError) {
        try createMetadata(at: path.metaDataURL, options: launchOptions)
    }
    
    // MARK: - Security & Access
    
    func createSecurityScopedBookmark(for url: URL) throws(VMFileSystemError) -> Data {
        let hasSecureAccess = url.startAccessingSecurityScopedResource()
        
        defer {
            if hasSecureAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: [
                    .fileSizeKey,
                    .totalFileSizeKey,
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityKey
                ],
                relativeTo: nil
            )
        } catch {
            throw VMFileSystemError.bookmarkCreationFailed(url: url, underlying: error)
        }
    }
    
    func validateSecurityAccess(for instance: VMInstance) throws(VMFileSystemError) {
        do {
            let url = try instance.getSecurityScopedURL()
            try validateSecurityAccessInternal(for: url)
        } catch URLBookmarkError.dataIsStale {
            throw VMFileSystemError.staleBookmarkData(instance: instance.name)
        } catch {
            throw VMFileSystemError.securityAccessValidationFailed(instance: instance.name, underlying: error)
        }
    }
    
    // MARK: - Cleanup Operations
    
    func cleanupTemporaryFiles(at path: VMBundlePath) throws(VMFileSystemError) {
        let accessGranted = path.url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                path.url.stopAccessingSecurityScopedResource()
            }
        }
        
        let restoreImagePath = path.restoreImageURL
        if FileManager.default.fileExists(atPath: restoreImagePath.path(percentEncoded: false)) {
            do {
                try FileManager.default.removeItem(at: restoreImagePath)
            } catch {
                // Non-critical error, log but don't throw
                NSLog("Warning: Could not clean up restore image at \(restoreImagePath): \(error)")
            }
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: path.url, includingPropertiesForKeys: nil)
            for url in contents where url.pathExtension == "tmp" {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            // Non-critical error
            NSLog("Warning: Could not clean up temporary files in \(path.url): \(error)")
        }
    }
    
    func archiveBundle(at path: VMBundlePath, to archivePath: URL) throws(VMFileSystemError) {
        print("Archive called")
        // TODO: - Copy VM Bundle from path.url to archivePath
    }
    
    func loadLaunchOptions(for bundlePath: VMBundlePath) -> LaunchOptions {
        let metadataURL = bundlePath.metaDataURL
        
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = BinaryMetadataCoder()
            return decoder.decodeLaunchOptions(from: data)
        } catch {
            NSLog("Warning: Could not load launch options for \(bundlePath.bundleName), using defaults: \(error)")
            return VMConfigHelper.defaultLaunchOptions
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func validateSecurityAccessInternal(for url: URL) throws(VMFileSystemError) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard accessGranted else {
            throw VMFileSystemError.securityAccessDenied(url: url)
        }
        
        // Test that we can actually read the directory
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch {
            throw VMFileSystemError.securityAccessTestFailed(url: url, underlying: error)
        }
    }
    
    private func createDiskImage(at url: URL, sizeInGb: UInt) async throws(VMFileSystemError) {
        do {
            try await Task.detached(name: "Create Disk Image", priority: .userInitiated) {
                try await self.diskUtilityClient.createDiskImage(
                    at: url,
                    sizeInGiB: sizeInGb
                )
            }.value
        } catch let error as DiskUtilityError {
            throw .diskUtilityError(error)
        } catch {
            assertionFailure("Only DiskUtilityError should be thrown here, but instead received \(error)")
        }
    }
    
    private func createAuxiliaryStorage(at url: URL, with hardwareModel: VZMacHardwareModel) throws(VMFileSystemError) {
        do {
            
            let _ = try VZMacAuxiliaryStorage(
                creatingStorageAt: url,
                hardwareModel: hardwareModel,
                options: []
            )
            // The creation above automatically writes the file
        } catch {
            throw VMFileSystemError.auxiliaryStorageCreationFailed(path: url, underlying: error)
        }
    }
    
    private func createHardwareModel(at url: URL, with hardwareModel: VZMacHardwareModel) throws(VMFileSystemError) {
        do {
            let data = hardwareModel.dataRepresentation
            try data.write(to: url)
        } catch {
            throw VMFileSystemError.configurationFileWriteFailed(underlying: error)
        }
    }
    
    private func createMachineIdentifier(at url: URL) throws(VMFileSystemError) {
        do {
            let machineIdentifier = VZMacMachineIdentifier()
            try machineIdentifier.dataRepresentation.write(to: url)
        } catch {
            throw VMFileSystemError.configurationFileWriteFailed(underlying: error)
        }
    }
    
    private func createMetadata(at url: URL, options: LaunchOptions) throws(VMFileSystemError) {
        let binaryCoder = BinaryMetadataCoder()
        let data = binaryCoder.encode(options)
        
        do {
            try data.write(to: url)
        } catch {
            throw VMFileSystemError.metadataWriteFailed(path: url, underlying: error)
        }
    }
    
    private func validateComponentIntegrity(component: BundleComponent, at url: URL) throws(VMFileSystemError) {
        do {
            switch component {
            case .bundle:
                break
            case .diskImage:
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
                guard let size = attributes[.size] as? Int64, size > 0 else {
                    throw VMFileSystemError.invalidDiskImage(url: url)
                }
            case .auxiliaryStorage:
                guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                    throw VMFileSystemError.missingAuxiliaryStorage(url: url)
                }
            case .hardwareModel:
                let data = try Data(contentsOf: url)
                guard VZMacHardwareModel(dataRepresentation: data) != nil else {
                    throw VMFileSystemError.invalidHardwareModel(url: url)
                }
            case .machineIdentifier:
                let data = try Data(contentsOf: url)
                guard VZMacMachineIdentifier(dataRepresentation: data) != nil else {
                    throw VMFileSystemError.invalidMachineIdentifier(url: url)
                }
            case .metadata:
                let data = try Data(contentsOf: url)
                let decoder = BinaryMetadataCoder()
                _ = decoder.decodeLaunchOptions(from: data)
            }
        } catch {
            throw .accessingDataFromUrl(url: url, underlying: error)
        }
    }
}

// MARK: - Error Types

enum VMFileSystemError: LocalizedError {
    case bundleCreationFailed(path: URL, underlying: Error)
    case bundleDeletionFailed(path: URL, underlying: Error)
    case bundleArchiveFailed(from: URL, to: URL, underlying: Error)
    case restoreImageCopyFailed(from: URL, to: URL, underlying: Error)
    case auxiliaryStorageCreationFailed(path: URL, underlying: Error)
    case configurationFileWriteFailed(underlying: Error)
    case metadataWriteFailed(path: URL, underlying: Error)
    case bookmarkCreationFailed(url: URL, underlying: Error)
    case securityAccessDenied(url: URL)
    case securityAccessTestFailed(url: URL, underlying: Error)
    case securityAccessValidationFailed(instance: String, underlying: Error)
    case staleBookmarkData(instance: String)
    case invalidConfiguration(String)
    case cannotRepairCriticalComponent(BundleComponent)
    case cannotRepairCorruptedComponent(BundleComponent, underlying: Error)
    case cannotRepairInaccessibleBundle(underlying: Error)
    case invalidDiskImage(url: URL)
    case missingAuxiliaryStorage(url: URL)
    case invalidHardwareModel(url: URL)
    case invalidMachineIdentifier(url: URL)
    case accessingDataFromUrl(url: URL, underlying: Error)
    case diskUtilityError(DiskUtilityError)
    
    var errorDescription: String? {
        switch self {
        case .bundleCreationFailed(let path, _):
            return "Failed to create VM bundle at \(path.path(percentEncoded: false))"
        case .bundleDeletionFailed(let path, _):
            return "Failed to delete VM bundle at \(path.path(percentEncoded: false))"
        case .restoreImageCopyFailed(let from, let to, _):
            return "Failed to copy restore image from \(from.lastPathComponent) to \(to.lastPathComponent)"
        case .securityAccessDenied(let url):
            return "Access denied to \(url.path(percentEncoded: false))"
        case .staleBookmarkData(let instance):
            return "VM '\(instance)' path is no longer accessible. Please relink the VM."
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .cannotRepairCriticalComponent(let component):
            return "Cannot repair critical component: \(component.rawValue). VM may need to be recreated."
        case .invalidDiskImage(let url):
            return "Disk image at \(url.lastPathComponent) is invalid or corrupted"
        case .invalidHardwareModel(let url):
            return "Hardware model file at \(url.lastPathComponent) is corrupted"
        case .invalidMachineIdentifier(let url):
            return "Machine identifier file at \(url.lastPathComponent) is corrupted"
        default:
            return "VM file system operation failed"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .staleBookmarkData:
            return "Use the 'Relink' option to reconnect to your VM bundle."
        case .cannotRepairCriticalComponent:
            return "Try importing the VM again or create a new one."
        case .securityAccessDenied:
            return "Check file permissions and ensure the VM bundle is accessible."
        case .invalidDiskImage:
            return "The disk image may be corrupted. Try creating a new VM."
        default:
            return "Check file permissions and available disk space."
        }
    }
}
