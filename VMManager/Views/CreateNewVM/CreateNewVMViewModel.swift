import Foundation
import Virtualization
import Combine

// TODO: - Use IPSW.me API to fetch different macOS IPSW version files based on device identifier

enum NewVMError: Error {
    case alreadyDownloading
}

@Observable
class CreateNewVMViewModel {
    private(set) var progress: VMCreationProgress?
    var launchOptions = VMConfigHelper.defaultLaunchOptions
    private let lifecycleService: VMLifecycleService
    private let configValidator: VMConfigurationValidator
    private(set) var error: VMValidationError.ResourceValidationError?
    
    init(progress: VMCreationProgress? = nil, launchOptions: LaunchOptions = VMConfigHelper.defaultLaunchOptions, lifecycleService: VMLifecycleService = VMLifecycleService(), configValidator: VMConfigurationValidator = VMConfigurationValidator()) {
        self.progress = progress
        self.launchOptions = launchOptions
        self.lifecycleService = lifecycleService
        self.configValidator = configValidator
    }
    
    func isDownloading() -> Bool {
        switch progress {
        case .complete, nil: return false
        default: return true
        }
    }
    
    func finish() {
        if case .complete = progress {
            progress = nil
        }
    }
    
    func validateLaunchOptions() {
        do {
            try configValidator.validateLaunchOptions(launchOptions)
        } catch {
            self.error = error
        }
    }
    
    func startInstallationProcess(withName name: String, andContainerURL containerURL: URL, usingIpswAt ipswURL: URL? = nil) async throws(NewVMError) -> Data {
        guard !isDownloading() else {
            throw .alreadyDownloading
        }
        
        let accessGranted = containerURL.startAccessingSecurityScopedResource()
        
        defer {
            if accessGranted {
                containerURL.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            for try await progress in lifecycleService.createAndInstallVM(
                configuration: VMCreationConfiguration(
                    name: name,
                    containerURL: containerURL,
                    launchOptions: launchOptions,
                    customIpswURL: ipswURL
                )
            ) {
                self.progress = progress
                
                if case let .complete(data) = progress {
                    return data
                }
            }
        } catch {
            print(error)
        }
        
        fatalError("Bad")
    }
}
