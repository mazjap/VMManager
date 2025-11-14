import SwiftUI
import Virtualization

struct ResourcesStep: View {
    @Binding private var launchOptions: LaunchOptions
    
    private let spaceAvailableInGb: UInt
    
    init(launchOptions: Binding<LaunchOptions>, spaceAvailableInGb: UInt) {
        self._launchOptions = launchOptions
        self.spaceAvailableInGb = spaceAvailableInGb
    }
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue.gradient)
                
                Text("Configure Resources")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Allocate hardware resources for your virtual machine")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 20)
            
            VStack(spacing: 24) {
                ResourceSlider(
                    icon: "cpu",
                    title: "CPU Cores",
                    value: $launchOptions.cpuCores,
                    range: UInt(VZVirtualMachineConfiguration.minimumAllowedCPUCount)...UInt(min(VZVirtualMachineConfiguration.maximumAllowedCPUCount, ProcessInfo.processInfo.processorCount)),
                    color: .blue,
                    formatter: { "\($0) cores" }
                )
                
                ResourceSlider(
                    icon: "memorychip",
                    title: "Memory (RAM)",
                    value: Binding(
                        get: { launchOptions.memoryGb },
                        set: { launchOptions.memoryGb = $0 }
                    ),
                    range: UInt(VZVirtualMachineConfiguration.minimumAllowedMemorySize / (1024 * 1024 * 1024))...UInt(min(VZVirtualMachineConfiguration.maximumAllowedMemorySize, ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)),
                    color: .purple,
                    formatter: { "\($0) GB" }
                )
                
                if spaceAvailableInGb <= 32 {
                    Text("Not enough space available to install vm on selected drive")
                } else {
                    ResourceSlider(
                        icon: "internaldrive",
                        title: "Disk Size",
                        value: $launchOptions.storageGb,
                        range: 32...spaceAvailableInGb, // TODO: - Make max disk space conform to how much space is available after checking the path provided.
                        color: .green,
                        formatter: { "\($0) GB" }
                    )
                }
            }
            .frame(maxWidth: 500)
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("Resources are only used when the VM is running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
    }
}
