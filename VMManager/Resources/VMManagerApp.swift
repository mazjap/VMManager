import SwiftUI
import SwiftData

// Get rid of fatalErrors and swap them with runtime user-interactive errors (graceful failure) (also fix try?s and try!s)
// Handle relevant TODOs
// Seperation of concerns/better project structure

@main
struct VMManagerApp: App {
    private var modelContainer = {
        let schema = Schema([VMInstance.self])
        let config = ModelConfiguration(schema: schema)
        
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            NSLog("While initializing the ModelContainer, an error occurred: \(error)")
            fatalError("While initializing the ModelContainer, an error occurred: \(error)")
        }
    }()
    
    init() {
        setenv("VZVirtualMachineLogLevel", "debug", 1)
        
        NSPasteboard.general.declareTypes([.string], owner: self)
    }
    
    var body: some Scene {
        // Launch VM Window
        WindowGroup {
            VmOverviewViewContainer()
                .modelContainer(modelContainer)
        }
        
        WindowGroup(id: WindowId.virtualMachine.rawValue, for: VmLaunchParameters.self) { params in
            let context = modelContainer.mainContext
            if let params = params.wrappedValue,
               let instance = context.model(for: params.instanceId) as? VMInstance {
                // TODO: - Some controls along the toolbar of the window
                VMInstanceSetupView(instance: InstanceManager(instance: instance, context: context, isInRecoveryMode: params.isInRecoveryMode))
            } else {
                Text("Ran into an issue: Configuration is nil")
            }
        }
        .restorationBehavior(.disabled)
        
        WindowGroup(id: WindowId.newVMOptions.rawValue) {
            CreateNewVMView()
                .modelContainer(modelContainer)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        
        WindowGroup(id: WindowId.editLaunchOptions.rawValue, for: PersistentIdentifier.self) { instanceId in
            let context = modelContainer.mainContext
            if let instanceId = instanceId.wrappedValue,
               let instance = context.model(for: instanceId) as? VMInstance {
                EditLaunchOptionsView(instance: instance)
                    .modelContainer(modelContainer)
            } else {
                Text("Failed to load VM instance")
            }
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        
        // TODO: VM Control window
        
        // TODO: VM Settings window
    }
}
