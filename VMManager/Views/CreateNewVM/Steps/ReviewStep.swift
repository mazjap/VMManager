import SwiftUI

struct ReviewStep: View {
    private let selectedVMType: VMType
    private let vmName: String
    private let vmPath: URL
    private let launchOptions: LaunchOptions
    private let useCustomIpsw: Bool
    private let customIpswURL: URL?
    private let linuxKernelPath: URL?
    
    init(selectedVMType: VMType, vmName: String, vmPath: URL, launchOptions: LaunchOptions, useCustomIpsw: Bool, customIpswURL: URL?, linuxKernelPath: URL?) {
        self.selectedVMType = selectedVMType
        self.vmName = vmName
        self.vmPath = vmPath
        self.launchOptions = launchOptions
        self.useCustomIpsw = useCustomIpsw
        self.customIpswURL = customIpswURL
        self.linuxKernelPath = linuxKernelPath
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 0)
            
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue.gradient)
                
                Text("Review Configuration")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Verify your settings before creating the VM")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 20)
            
            VStack(spacing: 16) {
                ReviewSection(title: "General") {
                    ReviewRow(label: "Type", value: selectedVMType == .macOS ? "macOS" : "Linux", icon: "square.grid.2x2")
                    ReviewRow(label: "Name", value: vmName, icon: "textformat.abc")
                    ReviewRow(label: "Location", value: vmPath.path(percentEncoded: false), icon: "folder", truncate: true)
                }
                
                ReviewSection(title: "Resources") {
                    ReviewRow(label: "CPU Cores", value: "\(launchOptions.cpuCores)", icon: "cpu")
                    ReviewRow(label: "Memory", value: "\(launchOptions.memoryGb) GB", icon: "memorychip")
                    ReviewRow(label: "Disk Size", value: "\(launchOptions.storageGb) GB", icon: "internaldrive")
                }
                
                ReviewSection(title: "Installation") {
                    if selectedVMType == .macOS {
                        if useCustomIpsw, let ipswURL = customIpswURL {
                            HStack {
                                Image(systemName: "doc.badge.gearshape")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Using custom IPSW file")
                                        .font(.subheadline)
                                    Text(ipswURL.path(percentEncoded: false))
                                        .help(ipswURL.path(percentEncoded: false))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                            }
                        } else {
                            HStack {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("macOS will be downloaded from Apple")
                                        .font(.subheadline)
                                    Text("Approximately 15 GB download")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        if let linuxKernelPath {
                            HStack {
                                Image(systemName: "doc.badge.gearshape")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Using custom Linux kernel")
                                        .font(.subheadline)
                                    Text(linuxKernelPath.lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                            }
                        } else {
                            ContentUnavailableView("No linux kernel selected", systemImage: "exclamationmark.octagon.fill", description: Text("An error has occured. Please try selecting the linux kernel again from the previous step."))
                        }
                    }
                }
            }
            .frame(maxWidth: 500)
            
            Spacer(minLength: 0)
        }
        .padding(40)
    }
}
