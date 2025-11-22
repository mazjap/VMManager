import Foundation
import Virtualization

class VMConfigurationValidator {
    private let fileSystemService: VMFileSystemService
    
    init(fileSystemService: VMFileSystemService = VMFileSystemService()) {
        self.fileSystemService = fileSystemService
    }
    
    // MARK: - System Validation
    
    /// Validates that the host system meets minimum requirements for VM creation
    func validateSystemRequirements() throws {
        guard VZVirtualMachineConfiguration.minimumAllowedCPUCount > 0 else {
            throw VMValidationError.virtualizationNotSupported
        }
        
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        let minimumMemory = UInt64(VZVirtualMachineConfiguration.minimumAllowedMemorySize)
        
        guard availableMemory >= minimumMemory * 2 else { // Need at least 2x minimum for host + VM
            throw VMValidationError.insufficientSystemMemory(
                available: availableMemory,
                required: minimumMemory * 2
            )
        }
        
        let availableCPUs = ProcessInfo.processInfo.processorCount
        let minimumCPUs = VZVirtualMachineConfiguration.minimumAllowedCPUCount
        
        guard availableCPUs >= minimumCPUs + 1 else { // Need at least 1 extra for host
            throw VMValidationError.insufficientCPUCores(
                available: availableCPUs,
                required: minimumCPUs + 1
            )
        }
    }
    
    // MARK: - Configuration Validation
    
    /// Validates a complete VM creation configuration
    func validateConfiguration(_ config: VMCreationConfiguration) async throws {
        try validateSystemRequirements()
        try validateLaunchOptions(config.launchOptions, requiresDisk: true)
        try validateDiskSpace(for: config.containerURL, requiredSize: config.launchOptions.storageGb)
        
        if let ipswURL = config.customIpswURL {
            _ = try await validateRestoreImage(at: ipswURL)
        }
        
        try validateVMName(config.name)
        try validateContainerPath(config.containerURL)
    }
    
    /// Validates launch options against system capabilities and VM requirements
    func validateLaunchOptions(_ options: LaunchOptions, for bundlePath: VMBundlePath? = nil, requiresDisk: Bool = false) throws {
        let maxCPUs = VZVirtualMachineConfiguration.maximumAllowedCPUCount
        let minCPUs = VZVirtualMachineConfiguration.minimumAllowedCPUCount
        let availableCPUs = ProcessInfo.processInfo.processorCount
        
        guard options.cpuCores >= UInt(minCPUs) else {
            throw VMValidationError.cpuCountTooLow(
                requested: options.cpuCores,
                minimum: UInt(minCPUs)
            )
        }
        
        guard options.cpuCores <= UInt(maxCPUs) else {
            throw VMValidationError.cpuCountTooHigh(
                requested: options.cpuCores,
                maximum: UInt(maxCPUs)
            )
        }
        
        // Leave at least 1 CPU for the host
        guard options.cpuCores < UInt(availableCPUs) else {
            throw VMValidationError.cpuCountExceedsAvailable(
                requested: options.cpuCores,
                available: UInt(availableCPUs - 1)
            )
        }
        
        let maxMemory = UInt64(VZVirtualMachineConfiguration.maximumAllowedMemorySize)
        let minMemory = UInt64(VZVirtualMachineConfiguration.minimumAllowedMemorySize)
        let requestedMemoryBytes = UInt64(options.memoryGb) * 1024 * 1024 * 1024
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        
        guard requestedMemoryBytes >= minMemory else {
            throw VMValidationError.memoryTooLow(
                requested: options.memoryGb,
                minimum: UInt(minMemory / (1024 * 1024 * 1024))
            )
        }
        
        guard requestedMemoryBytes <= maxMemory else {
            throw VMValidationError.memoryTooHigh(
                requested: options.memoryGb,
                maximum: UInt(maxMemory / (1024 * 1024 * 1024))
            )
        }
        
        // Leave at least 4GB for the host system
        let hostReservedMemory: UInt64 = 4 * 1024 * 1024 * 1024
        guard requestedMemoryBytes + hostReservedMemory <= availableMemory else {
            throw VMValidationError.memoryExceedsAvailable(
                requested: options.memoryGb,
                available: UInt((availableMemory - hostReservedMemory) / (1024 * 1024 * 1024))
            )
        }
        
        if requiresDisk {
            guard options.storageGb >= 32 else {
                throw VMValidationError.diskTooSmall(
                    requested: options.storageGb,
                    minimum: 32
                )
            }
            
            // Check if we're updating an existing VM
            if let bundlePath {
                let currentOptions = fileSystemService.loadLaunchOptions(for: bundlePath)
                if options.storageGb < currentOptions.storageGb {
                    throw VMValidationError.diskShrinkNotSupported(
                        current: currentOptions.storageGb,
                        requested: options.storageGb
                    )
                }
            }
        }
    }
    
    /// Validates available disk space for VM creation
    func validateDiskSpace(for containerURL: URL, requiredSize: UInt) throws {
        do {
            let storage = try containerURL.getStorage()
            let requiredBytes = Int(requiredSize) * 1024 * 1024 * 1024
            let safetyMargin = 2 * 1024 * 1024 * 1024 // 2GB safety margin
            
            guard storage.available >= requiredBytes + safetyMargin else {
                throw VMValidationError.insufficientDiskSpace(
                    available: UInt(storage.available / (1024 * 1024 * 1024)),
                    required: requiredSize + 2 // Include safety margin in error
                )
            }
        } catch let error as VMValidationError {
            throw error
        } catch {
            throw VMValidationError.diskSpaceCheckFailed(underlying: error)
        }
    }
    
    // MARK: - Hardware Model & Restore Image Validation
    
    /// Validates and loads a restore image, returning the configuration
    func validateRestoreImage(at url: URL) async throws -> VZMacOSRestoreImage {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Check if file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw VMValidationError.restoreImageNotFound(url: url)
        }
        
        // Validate it's a proper restore image
        return try await withCheckedThrowingContinuation { continuation in
            VZMacOSRestoreImage.load(from: url) { result in
                switch result {
                case .success(let restoreImage):
                    continuation.resume(returning: restoreImage)
                case .failure(let error):
                    continuation.resume(throwing: VMValidationError.invalidRestoreImage(url: url, underlying: error))
                }
            }
        }
    }
    
    /// Validates hardware model file integrity
    func validateHardwareModel(at bundlePath: VMBundlePath) throws -> VZMacHardwareModel {
        let hardwareModelURL = bundlePath.hardwareModelURL
        
        guard FileManager.default.fileExists(atPath: hardwareModelURL.path(percentEncoded: false)) else {
            throw VMValidationError.hardwareModelNotFound(bundlePath: bundlePath)
        }
        
        do {
            let data = try Data(contentsOf: hardwareModelURL)
            guard let hardwareModel = VZMacHardwareModel(dataRepresentation: data) else {
                throw VMValidationError.invalidHardwareModel(bundlePath: bundlePath)
            }
            
            guard hardwareModel.isSupported else {
                throw VMValidationError.hardwareModelNotSupported(bundlePath: bundlePath)
            }
            
            return hardwareModel
        } catch let error as VMValidationError {
            throw error
        } catch {
            throw VMValidationError.hardwareModelReadError(bundlePath: bundlePath, underlying: error)
        }
    }
    
    // MARK: - VM Configuration Validation
    
    /// Validates a complete VZVirtualMachineConfiguration
    func validateVMConfiguration(_ config: VZVirtualMachineConfiguration) throws {
        do {
            try config.validate()
        } catch {
            throw VMValidationError.configurationValidationFailed(underlying: error)
        }
        
        do {
            try config.validateSaveRestoreSupport()
        } catch {
            throw VMValidationError.saveRestoreNotSupported(underlying: error)
        }
    }
    
    /// Validates host compatibility for a specific VM instance
    func validateHostCompatibility(for instance: VMInstance) throws {
        // Validate hardware model compatibility
        _ = try validateHardwareModel(at: instance.bundlePath)
        
        // Validate current launch options
        let currentOptions = fileSystemService.loadLaunchOptions(for: instance.bundlePath)
        try validateLaunchOptions(currentOptions, for: instance.bundlePath)
        
        // Check if bundle components are present and valid
        let result = try fileSystemService.validateBundle(at: instance.bundlePath)
    }
    
    /// Validates upgrade compatibility between old and new configurations
    func validateUpgradeCompatibility(from oldOptions: LaunchOptions, to newOptions: LaunchOptions) throws {
        // Disk size cannot decrease
        if newOptions.storageGb < oldOptions.storageGb {
            throw VMValidationError.diskShrinkNotSupported(
                current: oldOptions.storageGb,
                requested: newOptions.storageGb
            )
        }
        
        // Validate the new options are within bounds
        try validateLaunchOptions(newOptions, requiresDisk: true)
    }
    
    // MARK: - Path and Name Validation
    
    private func validateVMName(_ name: String) throws {
        guard !name.isEmpty else {
            throw VMValidationError.nameEmpty
        }
        
        guard name.count <= 255 else {
            throw VMValidationError.nameTooLong(name: name, maxLength: 255)
        }
        
        // Check for macOS filesystem invalid characters
        // On APFS/HFS+, only colon (:) is truly forbidden in filenames
        // Forward slash (/) is the path separator and null (\0) is string terminator
        let invalidCharacters = CharacterSet(charactersIn: "/:\0")
        guard name.rangeOfCharacter(from: invalidCharacters) == nil else {
            throw VMValidationError.nameContainsInvalidCharacters(name: name)
        }
        
        // Check for names that start/end with whitespace (generally bad practice)
        guard name.trimmingCharacters(in: .whitespacesAndNewlines) == name else {
            throw VMValidationError.nameHasLeadingOrTrailingWhitespace(name: name)
        }
        
        // Check for invisible/problematic Unicode characters
        guard !name.contains("\u{202E}") && !name.contains("\u{202D}") else { // Right-to-left override characters
            throw VMValidationError.nameContainsInvalidCharacters(name: name)
        }
    }
    
    private func validateContainerPath(_ url: URL) throws {
        // Check if path exists
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw VMValidationError.containerPathNotFound(url: url)
        }
        
        // Check if it's a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw VMValidationError.containerPathNotDirectory(url: url)
        }
        
        // Check if it's writable
        guard FileManager.default.isWritableFile(atPath: url.path(percentEncoded: false)) else {
            throw VMValidationError.containerPathNotWritable(url: url)
        }
    }
}

// MARK: - Error Types

enum VMValidationError: LocalizedError {
    // System validation errors
    case virtualizationNotSupported
    case insufficientSystemMemory(available: UInt64, required: UInt64)
    case insufficientCPUCores(available: Int, required: Int)
    
    // Resource validation errors
    case cpuCountTooLow(requested: UInt, minimum: UInt)
    case cpuCountTooHigh(requested: UInt, maximum: UInt)
    case cpuCountExceedsAvailable(requested: UInt, available: UInt)
    case cpuReductionTooLarge(current: UInt, requested: UInt)
    
    case memoryTooLow(requested: UInt, minimum: UInt)
    case memoryTooHigh(requested: UInt, maximum: UInt)
    case memoryExceedsAvailable(requested: UInt, available: UInt)
    case memoryReductionTooLarge(current: UInt, requested: UInt)
    
    case diskTooSmall(requested: UInt, minimum: UInt)
    case diskShrinkNotSupported(current: UInt, requested: UInt)
    case insufficientDiskSpace(available: UInt, required: UInt)
    case diskSpaceCheckFailed(underlying: Error)
    
    // Restore image validation errors
    case restoreImageNotFound(url: URL)
    case restoreImageTooSmall(url: URL, size: Int64)
    case restoreImageAccessError(url: URL, underlying: Error)
    case invalidRestoreImage(url: URL, underlying: Error)
    
    // Hardware model validation errors
    case hardwareModelNotFound(bundlePath: VMBundlePath)
    case invalidHardwareModel(bundlePath: VMBundlePath)
    case hardwareModelNotSupported(bundlePath: VMBundlePath)
    case hardwareModelReadError(bundlePath: VMBundlePath, underlying: Error)
    
    // Configuration validation errors
    case configurationValidationFailed(underlying: Error)
    case saveRestoreNotSupported(underlying: Error)
    
    // Name and path validation errors
    case nameEmpty
    case nameTooLong(name: String, maxLength: Int)
    case nameContainsInvalidCharacters(name: String)
    case nameHasLeadingOrTrailingWhitespace(name: String)
    case nameIsReserved(name: String)
    
    case containerPathNotFound(url: URL)
    case containerPathNotDirectory(url: URL)
    case containerPathNotWritable(url: URL)
    
    var errorDescription: String? {
        switch self {
        case .virtualizationNotSupported:
            return "Virtualization is not supported on this system"
        case .insufficientSystemMemory(let available, let required):
            return "Insufficient system memory: \(available / (1024*1024*1024))GB available, \(required / (1024*1024*1024))GB required"
        case .insufficientCPUCores(let available, let required):
            return "Insufficient CPU cores: \(available) available, \(required) required"
        case .cpuCountTooLow(let requested, let minimum):
            return "CPU count too low: \(requested) requested, minimum \(minimum)"
        case .cpuCountTooHigh(let requested, let maximum):
            return "CPU count too high: \(requested) requested, maximum \(maximum)"
        case .cpuCountExceedsAvailable(let requested, let available):
            return "CPU count exceeds available: \(requested) requested, \(available) available"
        case .memoryTooLow(let requested, let minimum):
            return "Memory too low: \(requested)GB requested, minimum \(minimum)GB"
        case .memoryTooHigh(let requested, let maximum):
            return "Memory too high: \(requested)GB requested, maximum \(maximum)GB"
        case .memoryExceedsAvailable(let requested, let available):
            return "Memory exceeds available: \(requested)GB requested, \(available)GB available"
        case .diskTooSmall(let requested, let minimum):
            return "Disk size too small: \(requested)GB requested, minimum \(minimum)GB"
        case .diskShrinkNotSupported(let current, let requested):
            return "Cannot shrink disk from \(current)GB to \(requested)GB"
        case .insufficientDiskSpace(let available, let required):
            return "Insufficient disk space: \(available)GB available, \(required)GB required"
        case .restoreImageNotFound(let url):
            return "Restore image not found at \(url.lastPathComponent)"
        case .invalidRestoreImage(let url, _):
            return "Invalid restore image: \(url.lastPathComponent)"
        case .hardwareModelNotSupported:
            return "Hardware model is not supported on this system"
        case .nameEmpty:
            return "VM name cannot be empty"
        case .nameContainsInvalidCharacters(let name):
            return "VM name '\(name)' contains invalid characters"
        case .nameHasLeadingOrTrailingWhitespace(let name):
            return "VM name '\(name)' contains leading or trailing whitespace"
        case .containerPathNotWritable(let url):
            return "Cannot write to selected path: \(url.path(percentEncoded: false))"
        default:
            return "VM configuration validation failed"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .insufficientSystemMemory, .insufficientCPUCores:
            return "Try reducing the VM resource allocation or upgrade your system"
        case .cpuCountExceedsAvailable, .memoryExceedsAvailable:
            return "Reduce the allocated resources to leave some for the host system"
        case .diskShrinkNotSupported:
            return "Disk size can only be increased, not decreased"
        case .insufficientDiskSpace:
            return "Free up disk space or choose a different location"
        case .invalidRestoreImage:
            return "Select a valid macOS restore image (.ipsw file)"
        case .nameContainsInvalidCharacters:
            return "Use only letters, numbers, spaces, and basic punctuation"
        case .containerPathNotWritable:
            return "Choose a different location or check folder permissions"
        default:
            return "Check your configuration and try again"
        }
    }
}

