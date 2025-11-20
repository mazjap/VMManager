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
    private let vmLifecycleService = VMLifecycleService()
    
    init(instance: InstanceManager) {
        self.instance = instance
    }
    
    func startVirtualMachine() async throws {
        let successfullyAuthorized = instance.bundlePath.url.startAccessingSecurityScopedResource()
        defer {
            if successfullyAuthorized {
                instance.bundlePath.url.stopAccessingSecurityScopedResource()
            }
        }
        
        for try await progress in vmLifecycleService.startVM(instance.instance) {
            if case let .complete(vm) = progress {
                virtualMachine = vm
                instance.didStartVM()
            }
        }
    }
    
    func resumeVirtualMachine() async throws {
        if let virtualMachine {
            try await vmLifecycleService.resumeVM(virtualMachine)
        }
    }
    
    func pauseVirtualMachine() async throws {
        if let virtualMachine {
            try await vmLifecycleService.pauseVM(virtualMachine)
        }
    }
    
    func restoreVirtualMachine(paths: VmBundlePath) async throws {
        virtualMachine = try await vmLifecycleService.restoreVMState(for: instance.instance)
        instance.didStartVM()
    }
}
