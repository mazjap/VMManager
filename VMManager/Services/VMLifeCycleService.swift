import Foundation
import Virtualization
import Combine

// MARK: - Progress Types

enum VMCreationProgress: Equatable, Identifiable {
    case validating
    case downloadingRestoreImage(fraction: Double)
    case copyingRestoreImage
    case creatingBundle
    case creatingAuxiliaryFiles
    case installingMacOS(fraction: Double)
    case cleaningUp
    case complete(bookmarkData: Data)
    
    var id: String {
        switch self {
        case .validating: return "validating"
        case .downloadingRestoreImage(let fraction): return "downloading_\(fraction)"
        case .copyingRestoreImage: return "copying_restore"
        case .creatingBundle: return "creating_bundle"
        case .creatingAuxiliaryFiles: return "creating_aux"
        case .installingMacOS(let fraction): return "installing_\(fraction)"
        case .cleaningUp: return "cleaning"
        case .complete: return "complete"
        }
    }
}

fileprivate actor Box {
    var cancellable: AnyCancellable?
    
    func setCancellable(_ cancellable: AnyCancellable?) {
        self.cancellable = cancellable
    }
    
    func cancel() {
        cancellable?.cancel()
    }
}

enum VMResourceUpdateProgress: Equatable, Identifiable {
    case validating
    case resizingDisk(percentage: Int)
    case updatingMetadata
    case complete
    
    var id: String {
        switch self {
        case .validating: return "validating"
        case .resizingDisk(let percentage): return "resizing_\(percentage)"
        case .updatingMetadata: return "updating_metadata"
        case .complete: return "complete"
        }
    }
}

enum VMStartProgress: Equatable, Identifiable {
    case validatingBundle
    case loadingConfiguration
    case startingVM
    case complete(vm: VZVirtualMachine)
    
    var id: String {
        switch self {
        case .validatingBundle: return "validating_bundle"
        case .loadingConfiguration: return "loading_config"
        case .startingVM: return "starting_vm"
        case .complete: return "complete"
        }
    }
    
    static func == (lhs: VMStartProgress, rhs: VMStartProgress) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - VMLifecycleService

class VMLifecycleService {
    private let fileSystemService: VMFileSystemService
    private let validator: VMConfigurationValidator
    private let diskUtilityClient: DiskUtilityClient
    
    init(
        fileSystemService: VMFileSystemService = VMFileSystemService(),
        validator: VMConfigurationValidator = VMConfigurationValidator(),
        diskUtilityClient: DiskUtilityClient = DiskUtilityClient()
    ) {
        self.fileSystemService = fileSystemService
        self.validator = validator
        self.diskUtilityClient = diskUtilityClient
    }
    
    // MARK: - VM Creation with Progress
    
    /// Creates a new VM with complete setup and installation, reporting progress
    func createAndInstallVM(configuration: VMCreationConfiguration) -> AsyncThrowingStream<VMCreationProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Validation
                    continuation.yield(.validating)
                    try await validator.validateConfiguration(configuration)
                    
                    let bundlePath = VMBundlePath(containerURL: configuration.containerURL, bundleName: configuration.name)
                    
                    // Create bundle
                    continuation.yield(.creatingBundle)
                    try fileSystemService.createBundle(at: bundlePath)
                    
                    // Handle restore image (download or copy)
                    if let customIpswURL = configuration.customIpswURL {
                        continuation.yield(.copyingRestoreImage)
                        try await fileSystemService.copyRestoreImage(from: customIpswURL, to: bundlePath)
                    } else {
                        // Download with progress
                        for try await progress in downloadRestoreImage(to: bundlePath) {
                            continuation.yield(.downloadingRestoreImage(fraction: progress))
                        }
                    }
                    
                    let restoreImage = try await getRestoreImageFrom(ipswURL: bundlePath.restoreImageURL)
                    guard let macOSConfig = restoreImage.mostFeaturefulSupportedConfiguration else {
                        throw VMLifecycleError.installationFailed(underlying: NSError(domain: "VMLifecycle", code: 0, userInfo: [NSLocalizedDescriptionKey: "No supported macOS configuration found."]))
                    }
                    
                    // Create auxiliary files
                    continuation.yield(.creatingAuxiliaryFiles)
                    try await fileSystemService.createAuxiliaryFiles(at: bundlePath, config: configuration, hardwareModel: macOSConfig.hardwareModel)
                    
                    // Install macOS with progress
                    for try await progress in installMacOS(at: bundlePath, configuration: configuration, restoreImage: restoreImage) {
                        continuation.yield(.installingMacOS(fraction: progress))
                    }
                    
                    // Cleanup
                    continuation.yield(.cleaningUp)
                    try fileSystemService.cleanupTemporaryFiles(at: bundlePath)
                    
                    // Create bookmark and finish
                    let bookmarkData = try fileSystemService.createSecurityScopedBookmark(for: bundlePath.url)
                    continuation.yield(.complete(bookmarkData: bookmarkData))
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - VM Runtime Management with Progress
    
    /// Starts a VM with validation and proper configuration loading
    func startVM(_ instance: VMInstance, recoveryMode: Bool = false) -> AsyncThrowingStream<VMStartProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Validate bundle integrity first
                    continuation.yield(.validatingBundle)
                    let validationResult = try fileSystemService.validateBundle(at: instance.bundlePath)
                    guard case .valid = validationResult else {
                        throw VMLifecycleError.bundleNotReady(validationResult)
                    }
                    
                    // Load configuration
                    continuation.yield(.loadingConfiguration)
                    let launchOptions = fileSystemService.loadLaunchOptions(for: instance.bundlePath)
                    try validator.validateLaunchOptions(launchOptions, for: instance.bundlePath)
                    
                    // Create VM configuration
                    let config = try await createVMConfiguration(instance: instance, options: launchOptions)
                    let vm = VZVirtualMachine(configuration: config)
                    
                    // Start VM
                    continuation.yield(.startingVM)
                    let startOptions = VZMacOSVirtualMachineStartOptions()
                    startOptions.startUpFromMacOSRecovery = recoveryMode
                    
                    try await vm.start(options: startOptions)
                    
                    continuation.yield(.complete(vm: vm))
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Resource Management with Progress
    
    /// Updates VM resources by modifying disk size and metadata
    func updateVMResources(_ bundlePath: VMBundlePath, newOptions: LaunchOptions) -> AsyncThrowingStream<VMResourceUpdateProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Validate new configuration
                    continuation.yield(.validating)
                    try validator.validateLaunchOptions(newOptions, for: bundlePath, requiresDisk: true)
                    
                    // Load current options to check what changed
                    let currentOptions = fileSystemService.loadLaunchOptions(for: bundlePath)
                    try validator.validateUpgradeCompatibility(from: currentOptions, to: newOptions)
                    
                    // Update disk size if changed
                    if newOptions.storageGb != currentOptions.storageGb {
                        for try await progress in diskUtilityClient.resizeDiskImage(
                            at: bundlePath.diskImageURL,
                            toSizeInGiB: newOptions.storageGb
                        ) {
                            continuation.yield(.resizingDisk(percentage: progress))
                        }
                    }
                    
                    // Update metadata
                    continuation.yield(.updatingMetadata)
                    try fileSystemService.updateMetadata(at: bundlePath, launchOptions: newOptions)
                    
                    continuation.yield(.complete)
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Simple Operations (No Progress Needed)
    
    func stopVM(_ vm: VZVirtualMachine) async throws {
        try await vm.stop()
    }
    
    func pauseVM(_ vm: VZVirtualMachine) async throws {
        try await vm.pause()
    }
    
    func resumeVM(_ vm: VZVirtualMachine) async throws {
        try await vm.resume()
    }
    
    func saveVMState(_ vm: VZVirtualMachine, to instance: VMInstance) async throws {
        try await vm.saveMachineStateTo(url: instance.bundlePath.saveFileURL)
    }
    
    func restoreVMState(for instance: VMInstance) async throws -> VZVirtualMachine {
        let launchOptions = fileSystemService.loadLaunchOptions(for: instance.bundlePath)
        let config = try await createVMConfiguration(instance: instance, options: launchOptions)
        let virtualMachine = VZVirtualMachine(configuration: config)
        
        do {
            try await virtualMachine.restoreMachineStateFrom(url: instance.bundlePath.saveFileURL)
        } catch {
            // If restore fails, clean up save file and throw
            try? FileManager.default.removeItem(at: instance.bundlePath.saveFileURL)
            throw error
        }
        
        return virtualMachine
    }
    
    func repairVM(_ instance: VMInstance) async throws {
        try fileSystemService.repairBundle(at: instance.bundlePath)
        
        // Re-validate after repair
        let validationResult = try fileSystemService.validateBundle(at: instance.bundlePath)
        guard case .valid = validationResult else {
            throw VMLifecycleError.repairFailed(validationResult)
        }
    }
    
    func archiveVM(_ instance: VMInstance, to archivePath: URL) async throws {
        try fileSystemService.archiveBundle(at: instance.bundlePath, to: archivePath)
    }
    
    func deleteVM(_ instance: VMInstance) async throws {
        try fileSystemService.deleteBundle(at: instance.bundlePath)
    }
    
    // MARK: - Private Implementation with Progress
    
    private func downloadRestoreImage(to bundlePath: VMBundlePath) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let box = Box()
            
            VZMacOSRestoreImage.fetchLatestSupported { [box] result in
                let restoreImage: VZMacOSRestoreImage
                
                do {
                    restoreImage = try result.get()
                } catch {
                    continuation.finish(throwing: VMLifecycleError.downloadFailed(underlying: error))
                    return
                }
                
                let task = URLSession.shared.downloadTask(with: restoreImage.url) { localUrl, response, error in
                    if let error {
                        continuation.finish(throwing: VMLifecycleError.downloadFailed(underlying: error))
                        return
                    }
                    
                    guard let localUrl else {
                        continuation.finish(throwing: VMLifecycleError.downloadFailed(underlying: NSError(domain: "VMManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No local URL returned from download"])))
                        return
                    }
                    
                    Task {
                        do {
                            try FileManager.default.moveItem(at: localUrl, to: bundlePath.restoreImageURL)
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: VMLifecycleError.downloadFailed(underlying: error))
                        }
                        
                        await box.cancel()
                    }
                }
                
                let cancellable = task.publisher(for: \.progress.fractionCompleted)
                    .receive(on: DispatchQueue.main)
                    .sink { fractionComplete in
                        continuation.yield(fractionComplete)
                    }
                
                Task {
                    await box.setCancellable(cancellable)
                }
                
                task.resume()
            }
        }
    }
    
    private func installMacOS(at bundlePath: VMBundlePath, configuration: VMCreationConfiguration, restoreImage: VZMacOSRestoreImage) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let macOSConfiguration = restoreImage.mostFeaturefulSupportedConfiguration else {
                        continuation.finish(throwing: VMLifecycleError.installationFailed(underlying: NSError(domain: "VMManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No supported configuration available"])))
                        return
                    }
                    
                    guard macOSConfiguration.hardwareModel.isSupported else {
                        continuation.finish(throwing: VMLifecycleError.installationFailed(underlying: NSError(domain: "VMManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Hardware model not supported"])))
                        return
                    }
                    
                    let vmConfig = try await setupVirtualMachine(macOSConfiguration: macOSConfiguration, bundlePath: bundlePath, launchOptions: configuration.launchOptions)
                    let virtualMachine = VZVirtualMachine(configuration: vmConfig)
                    
                    let installer = VZMacOSInstaller(virtualMachine: virtualMachine, restoringFromImageAt: bundlePath.restoreImageURL)
                    
                    
                    let cancellable = installer.publisher(for: \.progress.fractionCompleted)
                        .receive(on: DispatchQueue.main)
                        .sink { fraction in
                            continuation.yield(fraction)
                        }
                    
                    let box = Box()
                    
                    Task {
                        await box.setCancellable(cancellable)
                    }
                    
                    installer.install { [box] result in
                        switch result {
                        case .success:
                            continuation.finish()
                        case .failure(let error):
                            continuation.finish(throwing: VMLifecycleError.installationFailed(underlying: error))
                        }
                        
                        Task {
                            await box.cancel()
                        }
                    }
                    
                } catch {
                    continuation.finish(throwing: VMLifecycleError.installationFailed(underlying: error))
                }
            }
        }
    }
    
    // MARK: - Other Private Helper Methods
    
    private func getRestoreImageFrom(ipswURL: URL) async throws -> VZMacOSRestoreImage {
        try await withCheckedThrowingContinuation { continuation in
            VZMacOSRestoreImage.load(from: ipswURL) { result in
                switch result {
                case .success(let restoreImage):
                    continuation.resume(returning: restoreImage)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func createVMConfiguration(instance: VMInstance, options: LaunchOptions) async throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()
        
        config.platform = try createMacPlatformConfiguration(bundlePath: instance.bundlePath)
        
        config.cpuCount = Int(options.cpuCores)
        config.memorySize = UInt64(options.memoryGb) * 1024 * 1024 * 1024
        
        config.bootLoader = VMConfigHelper.createBootLoader()
        config.audioDevices = [VMConfigHelper.createSoundDeviceConfiguration()]
        config.graphicsDevices = [VMConfigHelper.createGraphicsDeviceConfiguration()]
        config.networkDevices = [VMConfigHelper.createNetworkDeviceConfiguration()]
        config.storageDevices = [VMConfigHelper.createBlockDeviceConfiguration(paths: instance.bundlePath)]
        config.pointingDevices = [VMConfigHelper.createPointingDeviceConfiguration()]
        config.keyboards = VMConfigHelper.createKeyboardConfiguration()
        
        let spiceAgent = VZSpiceAgentPortAttachment()
        spiceAgent.sharesClipboard = options.sharesClipboard // TODO: Ask the user to install some VM tools to allow for clipboard sharing
        
        let portConfig = VZVirtioConsolePortConfiguration()
        portConfig.attachment = spiceAgent
        portConfig.name = VZSpiceAgentPortAttachment.spiceAgentPortName // Requires SPICE agent running inside of guest VM (UTM's vd_agent https://github.com/utmapp/vd_agent)
        
        let consoleDeviceConfiguration = VZVirtioConsoleDeviceConfiguration()
        consoleDeviceConfiguration.ports[0] = portConfig
        
        config.consoleDevices = [consoleDeviceConfiguration]
        
        try validator.validateVMConfiguration(config)
        
        return config
    }
    
    private func createMacPlatformConfiguration(bundlePath: VMBundlePath) throws -> VZMacPlatformConfiguration {
        let macPlatform = VZMacPlatformConfiguration()
        
        let hardwareModel = try validator.validateHardwareModel(at: bundlePath)
        macPlatform.hardwareModel = hardwareModel
        
        let machineIdentifierData = try Data(contentsOf: bundlePath.machineIdentifierURL)
        guard let machineIdentifier = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
            throw VMLifecycleError.configurationInvalid("Invalid machine identifier")
        }
        macPlatform.machineIdentifier = machineIdentifier
        
        let auxiliaryStorage = VZMacAuxiliaryStorage(url: bundlePath.auxiliaryStorageURL)
        macPlatform.auxiliaryStorage = auxiliaryStorage
        
        return macPlatform
    }
    
    private func setupVirtualMachine(macOSConfiguration: VZMacOSConfigurationRequirements, bundlePath: VMBundlePath, launchOptions: LaunchOptions) async throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()
        
        config.platform = try createMacPlatformConfigurationForInstall(macOSConfiguration: macOSConfiguration, bundlePath: bundlePath)
        config.cpuCount = Int(launchOptions.cpuCores)
        config.memorySize = UInt64(launchOptions.memoryGb) * 1024 * 1024 * 1024
        
        config.bootLoader = VMConfigHelper.createBootLoader()
        config.audioDevices = [VMConfigHelper.createSoundDeviceConfiguration()]
        config.graphicsDevices = [VMConfigHelper.createGraphicsDeviceConfiguration()]
        config.networkDevices = [VMConfigHelper.createNetworkDeviceConfiguration()]
        config.storageDevices = [VMConfigHelper.createBlockDeviceConfiguration(paths: bundlePath)]
        config.pointingDevices = [VMConfigHelper.createPointingDeviceConfiguration()]
        config.keyboards = VMConfigHelper.createKeyboardConfiguration()
        
        try validator.validateVMConfiguration(config)
        
        return config
    }
    
    private func createMacPlatformConfigurationForInstall(macOSConfiguration: VZMacOSConfigurationRequirements, bundlePath: VMBundlePath) throws -> VZMacPlatformConfiguration {
        let macPlatformConfiguration = VZMacPlatformConfiguration()
        
        let auxiliaryStorage = VZMacAuxiliaryStorage(url: bundlePath.auxiliaryStorageURL)
        macPlatformConfiguration.auxiliaryStorage = auxiliaryStorage
        macPlatformConfiguration.hardwareModel = macOSConfiguration.hardwareModel
        macPlatformConfiguration.machineIdentifier = VZMacMachineIdentifier()
        
        return macPlatformConfiguration
    }
}

enum VMLifecycleError: LocalizedError {
    case bundleNotReady(BundleValidationResult)
    case repairFailed(BundleValidationResult)
    case downloadFailed(underlying: Error)
    case installationFailed(underlying: Error)
    case configurationInvalid(String)
    
    var errorDescription: String? {
        switch self {
        case .bundleNotReady:
            return "VM bundle is not ready for launch"
        case .repairFailed:
            return "Failed to repair VM bundle"
        case .downloadFailed:
            return "Failed to download macOS restore image"
        case .installationFailed:
            return "VM installation failed"
        case .configurationInvalid(let reason):
            return "Invalid VM configuration: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .bundleNotReady:
            return "Try repairing the VM or recreating it"
        case .downloadFailed:
            return "Check your internet connection and try again"
        case .installationFailed:
            return "Ensure you have enough disk space and try again"
        default:
            return "Check your configuration and try again"
        }
    }
}
