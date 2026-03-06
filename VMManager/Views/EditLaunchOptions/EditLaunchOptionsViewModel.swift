import Foundation

@Observable
class EditLaunchOptionsViewModel {
    private let lifecycleService: VMLifecycleService
    let bundlePath: VMBundlePath
    let displayName: String
    let initialLaunchOptions: LaunchOptions
    var launchOptions: LaunchOptions
    var spaceAvailableInGb: UInt
    var saveError: Error?
    var isSaving = false
    var saveProgress: VMResourceUpdateProgress?
    
    init(lifecycleService: VMLifecycleService = VMLifecycleService(), bundlePath: VMBundlePath, displayName: String, initialLaunchOptions: LaunchOptions, spaceAvailableInGb: UInt, saveError: Error? = nil, isSaving: Bool = false, saveProgress: VMResourceUpdateProgress? = nil) {
        self.lifecycleService = lifecycleService
        self.bundlePath = bundlePath
        self.displayName = displayName
        self.initialLaunchOptions = initialLaunchOptions
        self.launchOptions = initialLaunchOptions
        self.spaceAvailableInGb = spaceAvailableInGb
        self.saveError = saveError
        self.isSaving = isSaving
        self.saveProgress = saveProgress
    }
    
    convenience init(instance: VMInstance, lifecycleService: VMLifecycleService = VMLifecycleService(), fileSystemService: VMFileSystemService = VMFileSystemService()) {
        let accessGranted = instance.bundlePath.url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                instance.bundlePath.url.stopAccessingSecurityScopedResource()
            }
        }
        
        let launchOptions = fileSystemService.loadLaunchOptions(for: instance.bundlePath)
        
        let available: Int
        
        do {
            available = try instance.bundlePath.url.getStorage().available
        } catch {
            print("unable to retreive available storage size")
            available = 128 * 1024 * 1024 * 1024
        }
        
        self.init(
            lifecycleService: lifecycleService,
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
        saveProgress = .validating
        saveError = nil
        isSaving = true
        
        let successfullyAuthorized = bundlePath.url.startAccessingSecurityScopedResource()
        defer {
            if successfullyAuthorized {
                bundlePath.url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            for try await progress in lifecycleService.updateVMResources(bundlePath, newOptions: launchOptions) {
                self.saveProgress = progress
            }
        } catch {
            NSLog("Failed to save launch options: \(error)")
            saveError = error
            isSaving = false
            saveProgress = nil
        }
        
        return false
    }
}
