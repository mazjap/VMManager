import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import Virtualization

enum VMType: Hashable {
    case macOS
    case linux
}

struct CreateNewVMViewErrors {
    var nameIsEmpty: Bool
    var pathError: Error?
}

enum FilePickerState {
    case selectingPath
    case selectingLinuxKernel
    case selectingMacosIPSW
}

enum VMCreationStep: Int, CaseIterable {
    case vmType = 0
    case nameAndPath = 1
    case resources = 2
    case review = 3
    
    var title: String {
        switch self {
        case .vmType: return "Choose Type"
        case .nameAndPath: return "Name & Path"
        case .resources: return "Resources"
        case .review: return "Review"
        }
    }
    
    var icon: String {
        switch self {
        case .vmType: return "square.grid.2x2"
        case .nameAndPath: return "textformat.abc"
        case .resources: return "cpu"
        case .review: return "checkmark.circle"
        }
    }
}

struct CreateNewVMView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismissWindow) private var dismissWindow
    
    @State private var model = CreateNewVMViewModel()
    @State private var currentStep: VMCreationStep = .vmType
    @State private var filePickerState: FilePickerState = .selectingLinuxKernel
    @State private var isFilePickerPresented = false
    
    @State private var selectedVMType = VMType.macOS
    @State private var linuxKernelPath: URL?
    @State private var customIpswURL: URL?
    @State private var vmName = "macOS VM" // TODO: Handle special characters
    @State private var useCustomIpsw = false
    @State private var vmPath: URL = FileManager.default.homeDirectoryForCurrentUser
    
    @State private var nameError: String?
    
    private var bundlePath: VmBundlePath {
        VmBundlePath(containerURL: vmPath, bundleName: vmName)
    }
    
    private var spaceAvailableInGb: UInt {
        do {
            let size = try vmPath.getStorage().available
            return UInt(size / (1024 * 1024 * 1024))
        } catch {
            return 512
        }
    }
    
    private var fileTypes: [UTType] {
        switch filePickerState {
        case .selectingLinuxKernel: [.data]
        case .selectingPath: [.directory]
        case .selectingMacosIPSW: [.ipsw]
        }
    }
    
    private var canProceedFromCurrentStep: Bool {
        switch currentStep {
        case .vmType:
            if selectedVMType == .macOS {
                // Can proceed if downloading from Apple OR has custom IPSW selected
                return !useCustomIpsw || customIpswURL != nil
            } else {
                return linuxKernelPath != nil
            }
        case .nameAndPath:
            return !vmName.isEmpty
        case .resources:
            return spaceAvailableInGb > 32
        case .review:
            return true
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            CreateNewVMHeader(currentStep: currentStep)
            
            Divider()
            
            switch currentStep {
            case .vmType:
                vmTypeStep
            case .nameAndPath:
                nameAndLocationStep
            case .resources:
                resourcesStep
            case .review:
                reviewStep
            }
            
            Divider()
            
            CreateNewVMFooter(
                currentStep: $currentStep,
                canProceedFromCurrentStep: canProceedFromCurrentStep,
                onCancel: {
                    dismissWindow()
                },
                onCreateAndInstall: {
                    createAndInstallVM()
                }
            )
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: fileTypes,
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                switch filePickerState {
                case .selectingPath:
                    vmPath = url
                case .selectingLinuxKernel:
                    linuxKernelPath = url
                case .selectingMacosIPSW:
                    customIpswURL = url
                }
            }
        }
        .sheet(item: Binding { model.progress } set: { _ in }) { progress in
            installationProgressSheet(progress: progress)
        }
    }
    
    // MARK: - Steps
    
    private var vmTypeStep: some View {
        VMTypeStep(
            selectedVMType: $selectedVMType,
            useCustomIpsw: $useCustomIpsw,
            customIpswURL: $customIpswURL,
            linuxKernelPath: $linuxKernelPath,
            filePickerState: $filePickerState,
            isFilePickerPresented: $isFilePickerPresented
        )
    }
    
    private var nameAndLocationStep: some View {
        NameAndLocationStep(
            vmName: $vmName,
            nameError: $nameError,
            filePickerState: $filePickerState,
            isFilePickerPresented: $isFilePickerPresented,
            bundlePath: bundlePath,
            validateName: { nameError = vmName.isEmpty ? "Name cannot be empty" : nil }
        )
    }
    
    private var resourcesStep: some View {
        ResourcesStep(
            launchOptions: $model.launchOptions,
            spaceAvailableInGb: spaceAvailableInGb
        )
    }
    
    private var reviewStep: some View {
        ReviewStep(
            selectedVMType: selectedVMType,
            vmName: vmName,
            vmPath: vmPath,
            launchOptions: model.launchOptions,
            useCustomIpsw: useCustomIpsw,
            customIpswURL: customIpswURL,
            linuxKernelPath: linuxKernelPath
        )
    }
    
    // MARK: - Installation Progress Sheet
    
    @ViewBuilder
    private func installationProgressSheet(progress: NewVMProgress) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: iconForProgress(progress))
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
            }
            
            VStack(spacing: 8) {
                Text(titleForProgress(progress))
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(descriptionForProgress(progress))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            switch progress {
            case let .downloadFraction(fraction):
                VStack(spacing: 12) {
                    ProgressView(value: fraction, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                    
                    HStack {
                        Text("\(Int(fraction * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(formatBytes(fraction))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 300)
                }
            case .copyingRestoreFile:
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                }
            case .creatingAuxFiles:
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                }
            case let .installFraction(fraction):
                VStack(spacing: 12) {
                    ProgressView(value: fraction, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                    
                    Text("\(Int(fraction * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .cleanup:
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                }
            case .complete:
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    
                    Button {
                        Task {
                            model.finish()
                            
                            try await Task.sleep(for: .seconds(0.2))
                            
                            dismissWindow()
                        }
                    } label: {
                        Text("Done")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(40)
        .frame(width: 450)
        .interactiveDismissDisabled(progress != .complete)
    }
    
    // MARK: - Helper Methods
    
    private func createAndInstallVM() {
        Task {
            do {
                let bookmarkData: Data =
                if useCustomIpsw, let customIpswURL {
                    try await model.startInstallationProcess(withName: vmName, andContainerURL: vmPath, usingIpswAt: customIpswURL)
                } else {
                    try await model.startInstallationProcess(withName: vmName, andContainerURL: vmPath)
                }
                
                let instance = VMInstance(name: vmName, bundlePath: bundlePath, pathBookmark: bookmarkData)
                instance.createdAt = .now
                context.insert(instance)
                
                try context.save()
            } catch {
                await MainActor.run {
                    print("Installation error: \(error)")
                }
            }
        }
    }
    
    private func formatBytes(_ fraction: Double) -> String {
        let estimatedTotal: Double = 15 * 1024 * 1024 * 1024
        let downloaded = estimatedTotal * fraction
        let gb = downloaded / (1024 * 1024 * 1024)
        
        if gb < 1 {
            let mb = downloaded / (1024 * 1024)
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.1f GB", gb)
        }
    }
    
    private func iconForProgress(_ progress: NewVMProgress) -> String {
        switch progress {
        case .downloadFraction: "arrow.down.circle.fill"
        case .copyingRestoreFile: "document.on.document.fill"
        case .creatingAuxFiles: "plus.circle.fill"
        case .installFraction: "gearshape.2.fill"
        case .cleanup: "trash.circle.fill"
        case .complete: "checkmark.circle.fill"
        }
    }
    
    private func titleForProgress(_ progress: NewVMProgress) -> String {
        switch progress {
        case .downloadFraction: "Downloading macOS"
        case .creatingAuxFiles: "Creating Auxiliary Files"
        case .copyingRestoreFile: "Copying Restore File"
        case .installFraction: "Installing Virtual Machine"
        case .cleanup: "Cleaning Up"
        case .complete: "Installation Complete"
        }
    }
    
    private func descriptionForProgress(_ progress: NewVMProgress) -> String {
        switch progress {
        case .downloadFraction: "Downloading the latest macOS restore image from Apple"
        case .copyingRestoreFile: "Copying the selected restore file to the location of your virtual machine"
        case .creatingAuxFiles: "Creating necessary files for the installation process"
        case .installFraction: "Installing macOS to the virtual machine disk"
        case .cleanup: "Cleaning up temporary files"
        case .complete: "Your virtual machine has been created successfully"
        }
    }
}

#Preview {
    CreateNewVMView()
}

// TODO: - Test:
// TEST: - Image snapshot testing of the review step with an image per possible configuration.
