import Foundation
import Virtualization
import Combine

// TODO: - Use IPSW.me API to fetch different macOS IPSW version files based on device identifier

enum NewVMError: Error {
    case noInstance
    case alreadyDownloading
    case whileFetchingLatestSupported(Error)
    case whileDownloadingRestoreImage(Error)
    case whileDownloadingRestoreImageNoLocalURL
    case whileCleaningUpRestoreImage(Error)
    case whileLoadingIpswFile(at: URL, Error)
    case couldNotMoveFile(from: URL, to: URL, error: Error)
    case failedToLaunchDiskUtil(Error)
    case failedToCreateDiskImage(terminationStatus: Int32)
    case failedToValidateConfig(Error)
    case whileInstallingMacOS(Error)
    case whileSettingUpAuxFiles(Error)
}

enum ProgressReport {
    case fraction(Double)
    case complete
}

enum NewVMProgress: Equatable, Identifiable {
    case downloadFraction(Double)
    case copyingRestoreFile
    case creatingAuxFiles
    case installFraction(Double)
//    case error(Error) // TODO: - Set error if there was a failure, handle presenting to the user in View
    case cleanup
    case complete
    
    var id: String {
        switch self {
        case let .downloadFraction(fraction):
            "download_\(fraction)"
        case .copyingRestoreFile:
            "copying_restore_file"
        case .creatingAuxFiles:
            "creating_aux_files"
        case let .installFraction(fraction):
            "install_\(fraction)"
        case .cleanup:
            "cleanup"
        case .complete:
            "complete"
        }
    }
}

@Observable
@MainActor
class CreateNewVMViewModel {
    private(set) var progress: NewVMProgress?
    var launchOptions = VMConfigHelper.defaultLaunchOptions
    
    func isDownloading() -> Bool {
        ![NewVMProgress.complete, nil].contains(progress)
    }
    
    func finish() {
        if progress == .complete {
            progress = nil
        }
    }
    
    @ObservationIgnored
    private var subscription: AnyCancellable?
    
    func startInstallationProcess(withName name: String, andContainerURL containerURL: URL, usingIpswAt ipswURL: URL? = nil) async throws(NewVMError) -> Data {
        guard !isDownloading() else {
            throw .alreadyDownloading
        }
        
        let containerAccessGranted = containerURL.startAccessingSecurityScopedResource()
        defer {
            if containerAccessGranted {
                containerURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let bundlePath = VmBundlePath(containerURL: containerURL, bundleName: name)
        
        try createVMBundle(paths: bundlePath)
        
        let bookmarkData: Data
        
        do {
            let bundleAccessGranted = bundlePath.url.startAccessingSecurityScopedResource()
            
            defer {
                if bundleAccessGranted {
                    bundlePath.url.stopAccessingSecurityScopedResource()
                }
            }
            
            bookmarkData = try bundlePath.url.bookmarkData(
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
            fatalError("Could not create bookmark data for the given path \(bundlePath.url.path(percentEncoded: false)), \(error)")
        }
        
        if let ipswURL {
            progress = .copyingRestoreFile
            
            do {
                let restoreImageURL = bundlePath.restoreImageURL
                try await Task.detached(name: "Copy IPSW File", priority: .userInitiated) {
                    let ipswAccessGranted = ipswURL.startAccessingSecurityScopedResource()
                    defer {
                        if ipswAccessGranted {
                            ipswURL.stopAccessingSecurityScopedResource()
                        }
                    }
                    
                    try FileManager.default.copyItem(at: ipswURL, to: restoreImageURL)
                }.value
            } catch {
                throw .whileLoadingIpswFile(at: ipswURL, error)
            }
        } else {
            progress = .downloadFraction(0)
            
            do {
                for try await progressReport in startDownload(paths: bundlePath) {
                    progress = .downloadFraction(progressReport)
                }
            } catch {
                progress = nil
                throw error as! NewVMError
            }
        }
        
        try await setUpVirtualMachineAuxiliaryFiles(paths: bundlePath)
        
        try await startInstallation(paths: bundlePath)
        
        try await cleanup(paths: bundlePath)
        
        progress = .complete
        
        return bookmarkData
    }
    
    nonisolated
    private func enqueueSubscription(_ subscription: AnyCancellable) {
        Task { @MainActor in
            self.subscription = subscription
        }
    }
    
    private func startDownload(paths: VmBundlePath) -> AsyncThrowingStream<Double, any Error> {
        AsyncThrowingStream(failure: NewVMError.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            VZMacOSRestoreImage.fetchLatestSupported { result in
                let restoreImage: VZMacOSRestoreImage
                
                do {
                    restoreImage = try result.get()
                } catch {
                    continuation.finish(throwing: .whileFetchingLatestSupported(error))
                    return
                }
                
                let task = URLSession.shared.downloadTask(with: restoreImage.url) { localUrl, response, error in
                    if let error {
                        continuation.finish(throwing: .whileDownloadingRestoreImage(error))
                        return
                    }
                    
                    if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                        print("Bad! \(response.statusCode)") // TODO: - Throw an error
                    }
                    
                    guard let localUrl else {
                        continuation.finish(throwing: NewVMError.whileDownloadingRestoreImageNoLocalURL)
                        return
                    }
                    
                    Task {
                        do {
                            try FileManager.default.moveItem(at: localUrl, to: paths.restoreImageURL)
                            continuation.finish()
                            return
                        } catch {
                            continuation.finish(throwing: .couldNotMoveFile(from: localUrl, to: paths.restoreImageURL, error: error))
                            return
                        }
                    }
                }
                
                self.enqueueSubscription(
                    task.publisher(for: \.progress.fractionCompleted)
                        .receive(on: DispatchQueue.main)
                        .sink { fractionComplete in
                            continuation.yield(fractionComplete)
                        }
                )
                
                task.resume()
            }
        }
    }
    
    private func cleanup(paths: VmBundlePath) async throws(NewVMError) {
        progress = .cleanup
        
        try await deleteRestoreImage(paths: paths)
    }
    
    private func deleteRestoreImage(paths: VmBundlePath) async throws(NewVMError) {
        do {
            try await Task.detached(name: "Delete restore image", priority: .userInitiated) {
                try FileManager.default.removeItem(at: paths.restoreImageURL)
            }.value
        } catch {
            throw .whileCleaningUpRestoreImage(error)
        }
    }
    
    private func setUpVirtualMachineAuxiliaryFiles(paths: VmBundlePath) async throws(NewVMError) {
        progress = .creatingAuxFiles
        
        try await createDiskImage(sizeInGiB: launchOptions.storageGb, paths: paths)
        try createMetadata(paths: paths)
    }
    
    private func startInstallation(paths: VmBundlePath) async throws(NewVMError) {
        progress = .installFraction(0)
        
        do {
            let restoreImage = try await VZMacOSRestoreImage.load(from: paths.restoreImageURL)
            
            guard let macOSConfiguration = restoreImage.mostFeaturefulSupportedConfiguration else {
                fatalError("No supported configuration available.")
            }

            if !macOSConfiguration.hardwareModel.isSupported {
                fatalError("macOSConfiguration configuration isn't supported on the current host.")
            }
            
            let config = try await setupVirtualMachine(macOSConfiguration: macOSConfiguration, paths: paths)
            let virtualMachine = VZVirtualMachine(configuration: config)
//            virtualMachineResponder = MacOSVirtualMachineDelegate()
//            virtualMachine.delegate = virtualMachineResponder
            
            for try await value in startInstallation(restoreImageURL: paths.restoreImageURL, virtualMachine: virtualMachine) {
                progress = .installFraction(value)
            }
        } catch {
            progress = nil
            throw error as! NewVMError
        }
    }
    
    private func createMacPlatformConfiguration(macOSConfiguration: VZMacOSConfigurationRequirements, paths: VmBundlePath) -> VZMacPlatformConfiguration {
        let macPlatformConfiguration = VZMacPlatformConfiguration()

        guard let auxiliaryStorage = try? VZMacAuxiliaryStorage(
            creatingStorageAt: paths.auxiliaryStorageURL,
            hardwareModel: macOSConfiguration.hardwareModel,
            options: []
        ) else {
            fatalError("Failed to create auxiliary storage.")
        }
        
        macPlatformConfiguration.auxiliaryStorage = auxiliaryStorage
        macPlatformConfiguration.hardwareModel = macOSConfiguration.hardwareModel
        macPlatformConfiguration.machineIdentifier = VZMacMachineIdentifier()
        
        try! macPlatformConfiguration.hardwareModel.dataRepresentation.write(to: paths.hardwareModelURL)
        try! macPlatformConfiguration.machineIdentifier.dataRepresentation.write(to: paths.machineIdentifierURL)

        return macPlatformConfiguration
    }
    
    private func createVMBundle(paths: VmBundlePath) throws(NewVMError) {
        do {
            try FileManager.default.createDirectory(atPath: paths.url.path(percentEncoded: false), withIntermediateDirectories: true)
        } catch {
            throw .whileSettingUpAuxFiles(error)
        }
    }
    
    @available(macOS 16.0, *)
    private func createDiskImage(sizeInGiB: UInt, paths: VmBundlePath) async throws(NewVMError) {
        do {
            try await Task.detached(name: "Create Disk Image", priority: .userInitiated) {
                let process = try Process.run(
                    URL(fileURLWithPath: "/usr/sbin/diskutil"),
                    arguments: [
                        "image", "create", "blank",
                        "--fs", "none", "--format",
                        "ASIF", "--size", "\(sizeInGiB)GiB",
                        paths.diskImageURL.path(percentEncoded: false)
                    ]
                )
                
                process.waitUntilExit()
                
                if process.terminationStatus != 0 {
                    throw NewVMError.failedToCreateDiskImage(terminationStatus: process.terminationStatus)
                }
            }.value
        } catch let error as NewVMError {
            throw error
        } catch {
            throw NewVMError.failedToLaunchDiskUtil(error)
        }
    }
    
    private func createMetadata(paths: VmBundlePath) throws(NewVMError) {
        let binaryCoder = BinaryMetadataCoder()
        let data = binaryCoder.encode(launchOptions)
        
        do {
            try data.write(to: paths.metaDataURL)
        } catch {
            throw .whileSettingUpAuxFiles(error)
        }
    }
    
    private func setupVirtualMachine(macOSConfiguration: VZMacOSConfigurationRequirements, paths: VmBundlePath) async throws(NewVMError) -> VZVirtualMachineConfiguration {
        let virtualMachineConfiguration = VZVirtualMachineConfiguration()
        
        virtualMachineConfiguration.platform = createMacPlatformConfiguration(macOSConfiguration: macOSConfiguration, paths: paths)
        virtualMachineConfiguration.cpuCount = Int(launchOptions.cpuCores)
        if virtualMachineConfiguration.cpuCount < macOSConfiguration.minimumSupportedCPUCount {
            fatalError("CPUCount isn't supported by the macOS configuration.")
        }
        
        virtualMachineConfiguration.memorySize = UInt64(launchOptions.memoryGb * (1024 * 1024 * 1024))
        if virtualMachineConfiguration.memorySize < macOSConfiguration.minimumSupportedMemorySize {
            fatalError("memorySize isn't supported by the macOS configuration.")
        }
        
        virtualMachineConfiguration.bootLoader = VMConfigHelper.createBootLoader()
        
        virtualMachineConfiguration.audioDevices = [VMConfigHelper.createSoundDeviceConfiguration()]
        virtualMachineConfiguration.graphicsDevices = [VMConfigHelper.createGraphicsDeviceConfiguration()]
        virtualMachineConfiguration.networkDevices = [VMConfigHelper.createNetworkDeviceConfiguration()]
        virtualMachineConfiguration.storageDevices = [VMConfigHelper.createBlockDeviceConfiguration(paths: paths)]
        
        virtualMachineConfiguration.pointingDevices = [VMConfigHelper.createPointingDeviceConfiguration()]
        virtualMachineConfiguration.keyboards = VMConfigHelper.createKeyboardConfiguration()
        
        do {
            try virtualMachineConfiguration.validate()
            try virtualMachineConfiguration.validateSaveRestoreSupport()
        } catch {
            throw .failedToValidateConfig(error)
        }
        
        return virtualMachineConfiguration
    }

    private func startInstallation(restoreImageURL: URL, virtualMachine: VZVirtualMachine) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream(failure: NewVMError.self) { continuation in
            let installer = VZMacOSInstaller(virtualMachine: virtualMachine, restoringFromImageAt: restoreImageURL)
            
            installer.install(completionHandler: { result in
                switch result {
                case let .failure(error):
                    continuation.finish(throwing: .whileInstallingMacOS(error))
                    return
                case .success:
                    continuation.finish()
                    return
                }
            })
            
            self.enqueueSubscription(
                installer.publisher(for: \.progress.fractionCompleted)
                    .receive(on: DispatchQueue.main)
                    .sink { fraction in
                        continuation.yield(fraction)
                    }
            )
        }
    }
}
