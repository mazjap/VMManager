import Foundation
import Virtualization

enum VMInitError: LocalizedError {
    case hwModelDataIssue(Error)
    case badHwModelData
    case machIdDataIssue(Error)
    case badMachIdData
    case hwNotSupported
    case requiredPathNotFound(URL)
    
    var localizedDescription: String {
        switch self {
        case let .hwModelDataIssue(error):
            "Failed to retrieve hardware model data: \(error)"
        case .badHwModelData:
            "Failed to create hardware model"
        case let .machIdDataIssue(error):
            "Failed to retrieve machine identifier data: \(error)"
        case .badMachIdData:
            "Failed to create machine id"
        case .hwNotSupported:
            "The hardware model isn't supported on the current host"
        case let .requiredPathNotFound(url):
            "Requred file not found at path: \(url.path(percentEncoded: false))"
        }
    }
}

enum VMStatusError: LocalizedError {
    case vmNotInitialized
    
    var localizedError: String {
        switch self {
        case .vmNotInitialized:
            "VM has not been setup with a configuration"
        }
    }
}

@Observable
class VMInstanceViewModel {
    var instance: InstanceManager
    private(set) var virtualMachine: VZVirtualMachine?
    var onVMQuit: (() -> Void)?
    
    init(instance: InstanceManager) {
        self.instance = instance
    }
    
    private func platformConfig(paths: VmBundlePath) throws -> VZMacPlatformConfiguration {
        let macPlatform = VZMacPlatformConfiguration()
        
        let auxiliaryStorage = VZMacAuxiliaryStorage(url: paths.auxiliaryStorageURL)
        macPlatform.auxiliaryStorage = auxiliaryStorage
        
        if !FileManager.default.fileExists(atPath: paths.url.path(percentEncoded: false)) {
            throw VMInitError.requiredPathNotFound(paths.url)
        }
        
        let hardwareModelData: Data
        
        do {
            hardwareModelData = try Data(contentsOf: paths.hardwareModelURL)
        } catch {
            throw VMInitError.hwModelDataIssue(error)
        }
        
        guard let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
            throw VMInitError.badHwModelData
        }
        
        guard hardwareModel.isSupported else {
            throw VMInitError.hwNotSupported
        }
        
        macPlatform.hardwareModel = hardwareModel
        
        let machineIdentifierData: Data
        
        do {
            machineIdentifierData = try Data(contentsOf: paths.machineIdentifierURL)
        } catch {
            throw VMInitError.machIdDataIssue(error)
        }
        
        guard let machineIdentifier = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
            throw VMInitError.badMachIdData
        }
        
        macPlatform.machineIdentifier = machineIdentifier
        
        return macPlatform
    }
    
    func configure() throws -> VZVirtualMachine {
        let config = VZVirtualMachineConfiguration()
        
        config.platform = try platformConfig(paths: instance.bundlePath)
        
        var launchOptions = VMConfigHelper.defaultLaunchOptions
        
        do {
            let data = try Data(contentsOf: instance.bundlePath.metaDataURL)
            launchOptions = try BinaryMetadataCoder().decodeLaunchOptions(from: data)
            print("✅ Using launch options from filesystem: \(launchOptions)")
        } catch {
            print(error)
            print("🚨 Using default launch options (not from filesystem): \(launchOptions)")
        }
        
        config.cpuCount = Int(launchOptions.cpuCores)
        config.memorySize = UInt64(launchOptions.memoryGb * (1024 * 1024 * 1024))
        
        config.bootLoader = VMConfigHelper.createBootLoader()
        
        config.audioDevices = [VMConfigHelper.createSoundDeviceConfiguration()]
        config.graphicsDevices = [VMConfigHelper.createGraphicsDeviceConfiguration()]
        config.networkDevices = [VMConfigHelper.createNetworkDeviceConfiguration()]
        config.storageDevices = [VMConfigHelper.createBlockDeviceConfiguration(paths: instance.bundlePath)]
        config.pointingDevices = [VMConfigHelper.createPointingDeviceConfiguration()]
        config.keyboards = VMConfigHelper.createKeyboardConfiguration()
        
        try config.validate()
        try config.validateSaveRestoreSupport()
        
        return VZVirtualMachine(configuration: config)
    }
    
    func startVirtualMachine() async throws {
        let successfullyAuthorized = instance.bundlePath.url.startAccessingSecurityScopedResource()
        defer {
            if successfullyAuthorized {
                instance.bundlePath.url.stopAccessingSecurityScopedResource()
            }
        }
        
        let virtualMachine = try self.configure()
        self.virtualMachine = virtualMachine
        
        let options = VZMacOSVirtualMachineStartOptions()
        
        if instance.isInRecoveryMode {
            options.startUpFromMacOSRecovery = true
        }
        
        try await virtualMachine.start(options: options)
        instance.didStartVM()
    }
    
    func resumeVirtualMachine() async throws {
        guard let virtualMachine else {
            throw VMStatusError.vmNotInitialized
        }
        
        try await virtualMachine.resume()
    }
    
    func restoreVirtualMachine(paths: VmBundlePath) async throws {
        guard let virtualMachine else {
            throw VMStatusError.vmNotInitialized
        }
        
        var errorWhenRestoring: Error?
        
        do {
            try await virtualMachine.restoreMachineStateFrom(url: paths.saveFileURL)
        } catch {
            errorWhenRestoring = error
        }
        
        try FileManager.default.removeItem(at: paths.saveFileURL)
        
        if errorWhenRestoring == nil {
            try await resumeVirtualMachine()
        } else {
            try await startVirtualMachine()
        }
    }
}
