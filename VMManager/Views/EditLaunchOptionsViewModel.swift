import Foundation

@Observable
class EditLaunchOptionsViewModel {
    private let diskUtilClient: DiskUtilityClient
    let bundlePath: VmBundlePath
    let displayName: String
    let initialLaunchOptions: LaunchOptions
    var launchOptions: LaunchOptions
    var spaceAvailableInGb: UInt
    var saveError: Error?
    var isSaving = false
    var saveProgress: SaveProgress?
    
    init(diskUtilClient: DiskUtilityClient = DiskUtilityClient(), bundlePath: VmBundlePath, displayName: String, initialLaunchOptions: LaunchOptions, spaceAvailableInGb: UInt, saveError: Error? = nil, isSaving: Bool = false, saveProgress: SaveProgress? = nil) {
        self.diskUtilClient = diskUtilClient
        self.bundlePath = bundlePath
        self.displayName = displayName
        self.initialLaunchOptions = initialLaunchOptions
        self.launchOptions = initialLaunchOptions
        self.spaceAvailableInGb = spaceAvailableInGb
        self.saveError = saveError
        self.isSaving = isSaving
        self.saveProgress = saveProgress
    }
    
    convenience init(instance: VMInstance, diskUtilClient: DiskUtilityClient = DiskUtilityClient()) {
        let accessGranted = instance.bundlePath.url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                instance.bundlePath.url.stopAccessingSecurityScopedResource()
            }
        }
        
        let launchOptions: LaunchOptions
        
        do {
            // TODO: - Fix this blocking the main thread
            let data = try Data(contentsOf: instance.bundlePath.metaDataURL)
            let binaryCoder = BinaryMetadataCoder()
            let initialLaunchOptions = binaryCoder.decodeLaunchOptions(from: data)
            launchOptions = initialLaunchOptions
        } catch {
            print("unable to load launch options from \(instance.bundlePath.metaDataURL): \(error)")
            launchOptions = VMConfigHelper.defaultLaunchOptions
        }
        
        let available: Int
        
        do {
            available = try instance.bundlePath.url.getStorage().available
        } catch {
            print("unable to retreive available storage size")
            available = 128 * 1024 * 1024 * 1024
        }
        
        self.init(
            diskUtilClient: diskUtilClient,
            bundlePath: instance.bundlePath,
            displayName: instance.name,
            initialLaunchOptions: launchOptions,
            spaceAvailableInGb: UInt(available / (1024 * 1024 * 1024)),
            saveError: nil,
            isSaving: false,
            saveProgress: nil
        )
    }
    
    func saveChanges() async -> Bool {
        saveProgress = .saveMetadata
        saveError = nil
        isSaving = true
        
        let binaryCoder = BinaryMetadataCoder()
        let data = binaryCoder.encode(launchOptions)
        
        let successfullyAuthorized = bundlePath.url.startAccessingSecurityScopedResource()
        defer {
            if successfullyAuthorized {
                bundlePath.url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let currentLaunchOptions = launchOptions
            if initialLaunchOptions.storageGb != currentLaunchOptions.storageGb {
                saveProgress = .resizeDiskImage(0)
                for try await percentage in diskUtilClient.resizeDiskImage(at: bundlePath.diskImageURL, toSizeInGiB: launchOptions.storageGb) {
                    print("Progress: \(percentage)%")
                    saveProgress = .resizeDiskImage(percentage)
                }
            }
            
            saveProgress = .saveMetadata
            
            let metaDataURL = bundlePath.metaDataURL
            
            try await Task.detached(name: "Save Launch Option changes", priority: .userInitiated) {
                if self.initialLaunchOptions != currentLaunchOptions {
                    try data.write(to: metaDataURL)
                    print("Successfully saved launch options: \(currentLaunchOptions)")
                } else {
                    print("Launch options were unchanged")
                }
            }.value
            
            isSaving = false
            
            return true
        } catch {
            print("Failed to save launch options: \(error)")
            saveError = error
            isSaving = false
        }
        
        return false
    }
}
