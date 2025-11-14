import SwiftUI
import Virtualization

struct VirtualMachineInstanceView: NSViewRepresentable {
    let vmModel: VMInstanceViewModel
    
    init(vmModel: VMInstanceViewModel) {
        self.vmModel = vmModel
    }
    
    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        
        view.virtualMachine = vmModel.virtualMachine
        view.automaticallyReconfiguresDisplay = true
        view.capturesSystemKeys = true
        
        vmModel.virtualMachine?.delegate = context.coordinator
        
        return view
    }
    
    func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {
        nsView.virtualMachine = vmModel.virtualMachine
        vmModel.virtualMachine?.delegate = context.coordinator
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(vmModel: vmModel)
    }
    
    class Coordinator: NSObject, VZVirtualMachineDelegate {
        let vmModel: VMInstanceViewModel
        
        init(vmModel: VMInstanceViewModel) {
            self.vmModel = vmModel
            super.init()
        }
        
        func guestDidStop(_ virtualMachine: VZVirtualMachine) {
            vmModel.onVMQuit?()
            NSLog("Guest did stop virtual machine")
        }
        
        func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: any Error) {
            vmModel.onVMQuit?()
            NSLog("Virtual machine did stop with error: \(error)")
        }
        
        func virtualMachine(_ virtualMachine: VZVirtualMachine, networkDevice: VZNetworkDevice, attachmentWasDisconnectedWithError error: any Error) {
            NSLog("Virtual machine network device disconnected with error: \(error)")
        }
    }
}
