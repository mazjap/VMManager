import SwiftUI
import Virtualization

struct VMInstanceSetupView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model: VMInstanceViewModel
    @State private var isAccessingSecureResource = false
    
    init(instance: InstanceManager) {
        self.model = VMInstanceViewModel(instance: instance)
    }
    
    var body: some View {
        VirtualMachineInstanceView(vmModel: model)
            .task {
                do {
                    try await model.startVirtualMachine()
                } catch VMInitError.hwModelDataIssue(let error) {
                    fatalError("TODO: - Alert user that VM is damaged and can't be used. Error: \(error)")
                } catch {
                    fatalError("\(error)")
                }
            }
            .onAppear {
                model.onVMQuit = {
                    dismissWindow()
                }
            }
            .onDisappear {
                if let vm = model.virtualMachine,
                   vm.state != .stopped {
                    Task {
                        do {
                            try await vm.stop()
                            print("VM Stopped")
                        } catch {
                            print("\(error)")
                        }
                    }
                }
            }
    }
}
