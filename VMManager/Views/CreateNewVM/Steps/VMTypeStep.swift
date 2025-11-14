import SwiftUI

struct VMTypeStep: View {
    @Binding private var selectedVMType: VMType
    @Binding private var useCustomIpsw: Bool
    @Binding private var customIpswURL: URL?
    @Binding private var linuxKernelPath: URL?
    @Binding private var filePickerState: FilePickerState
    @Binding private var isFilePickerPresented: Bool
    
    init(selectedVMType: Binding<VMType>, useCustomIpsw: Binding<Bool>, customIpswURL: Binding<URL?>, linuxKernelPath: Binding<URL?>, filePickerState: Binding<FilePickerState>, isFilePickerPresented: Binding<Bool>) {
        self._selectedVMType = selectedVMType
        self._useCustomIpsw = useCustomIpsw
        self._customIpswURL = customIpswURL
        self._linuxKernelPath = linuxKernelPath
        self._filePickerState = filePickerState
        self._isFilePickerPresented = isFilePickerPresented
    }
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue.gradient)
                
                Text("Choose Operating System")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Select the type of virtual machine you want to create")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 20)
            
            HStack(spacing: 20) {
                VMTypeCard(
                    systemImage: "apple.logo",
                    title: "macOS",
                    description: "Create a macOS virtual machine with automatic installation",
                    isSelected: selectedVMType == .macOS,
                    isAvailable: true
                ) {
                    selectedVMType = .macOS
                }
                
                VMTypeCard(
                    image: "linux",
                    title: "Linux",
                    description: "Create a Linux virtual machine (coming soon)",
                    isSelected: selectedVMType == .linux,
                    isAvailable: false
                ) {
                    selectedVMType = .linux
                }
            }
            .frame(maxWidth: 600)
            
            if selectedVMType == .macOS {
                macosIpswOptions
            }
            
            if selectedVMType == .linux {
                linuxKernelOptions
            }
        }
        .padding(40)
    }
    
    private var macosIpswOptions: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 12) {
                Toggle(isOn: $useCustomIpsw) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use custom IPSW file")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Provide your own macOS restore image instead of downloading")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: useCustomIpsw) { _, newValue in
                    if !newValue {
                        customIpswURL = nil
                    }
                }
                
                if useCustomIpsw {
                    VStack(spacing: 12) {
                        Button {
                            filePickerState = .selectingMacosIPSW
                            isFilePickerPresented = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text(customIpswURL == nil ? "Select IPSW File" : "Change IPSW File")
                            }
                            .frame(maxWidth: 300)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        
                        if let ipswURL = customIpswURL {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                
                                Text(ipswURL.lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                
                                Text("Please select an IPSW file to continue")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("macOS will be downloaded from Apple (~15 GB)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 500)
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var linuxKernelOptions: some View {
        VStack(spacing: 12) {
            Button {
                filePickerState = .selectingLinuxKernel
                isFilePickerPresented = true
            } label: {
                HStack {
                    Image(systemName: "doc.badge.plus")
                    Text(linuxKernelPath == nil ? "Select Kernel Image" : "Kernel Selected")
                }
                .frame(maxWidth: 300)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
            if let kernelPath = linuxKernelPath {
                Text(kernelPath.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
