import SwiftUI
import SwiftData
import Virtualization

enum SaveProgress: Equatable {
    case resizeDiskImage(Int)
    case saveMetadata
}

struct EditLaunchOptionsView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.modelContext) private var modelContext
    
    private let instance: VMInstance
    private let diskUtilClient = DiskUtilityClient()
    private let initialLaunchOptions: LaunchOptions
    @State private var launchOptions: LaunchOptions
    @State private var spaceAvailableInGb: UInt
    @State private var saveError: Error?
    @State private var isSaving = false
    @State private var saveProgress: SaveProgress?
    
    init(instance: VMInstance) {
        self.instance = instance
        
        let accessGranted = instance.bundlePath.url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                instance.bundlePath.url.stopAccessingSecurityScopedResource()
            }
        }
        
        // TODO: - Determine if State(initialValue:) in initializer is still bad practice
        
        do {
            let data = try Data(contentsOf: instance.bundlePath.metaDataURL)
            let binaryCoder = BinaryMetadataCoder()
            let initialLaunchOptions = try binaryCoder.decodeLaunchOptions(from: data)
            self.initialLaunchOptions = initialLaunchOptions
            self._launchOptions = State(initialValue: initialLaunchOptions)
        } catch {
            print("unable to load launch options from \(instance.bundlePath.metaDataURL): \(error)")
            self.initialLaunchOptions = VMConfigHelper.defaultLaunchOptions
            self._launchOptions = State(initialValue: VMConfigHelper.defaultLaunchOptions)
        }
        if let data = FileManager.default.contents(atPath: instance.bundlePath.metaDataURL.path(percentEncoded: false)) {
            let binaryCoder = BinaryMetadataCoder()
            self._launchOptions = State(initialValue: (try? binaryCoder.decodeLaunchOptions(from: data)) ?? VMConfigHelper.defaultLaunchOptions)
        } else {
            self._launchOptions = State(initialValue: VMConfigHelper.defaultLaunchOptions)
        }
        
        let available = (try? instance.bundlePath.url.getStorage().available) ?? (128 * 1024 * 1024 * 1024)
        self._spaceAvailableInGb = State(initialValue: UInt(available / (1024 * 1024 * 1024)))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()
            
            ResourcesStep(
                launchOptions: $launchOptions,
                spaceAvailableInGb: spaceAvailableInGb
            )
            
            Divider()
            
            footer
        }
        .sheet(isPresented: $isSaving) {
            if let saveProgress {
                savingProgressSheet(progress: saveProgress)
            } else {
                EmptyView()
                    .onAppear {
                        isSaving = false
                    }
            }
        }
        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") {
                saveError = nil
            }
        } message: {
            if let error = saveError {
                Text(error.localizedDescription)
            }
        }
    }
    
    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title)
                    .foregroundStyle(.blue.gradient)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Launch Options")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(instance.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var footer: some View {
        HStack(spacing: 12) {
            Button(role: .cancel) {
                dismissWindow()
            } label: {
                Text("Cancel")
                    .frame(minWidth: 80)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button {
                Task {
                    await saveChanges()
                }
            } label: {
                HStack {
                    Text("Save")
                    Image(systemName: "checkmark.circle.fill")
                }
                .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func savingProgressSheet(progress: SaveProgress) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                if case let .resizeDiskImage(percentage) = progress {
                    ZStack {
                        Circle()
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 8)
                            .frame(width: 64, height: 64)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(percentage) / 100.0)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 64, height: 64)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.3), value: percentage)
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                }
            }
            
            VStack(spacing: 8) {
                if case let .resizeDiskImage(percentage) = progress {
                    Text("Resizing Disk Image")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(percentage)% complete")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Saving Changes")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Preparing to save...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            if progress == .saveMetadata {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 300)
            }
        }
        .padding(40)
        .frame(width: 450)
        .interactiveDismissDisabled()
    }
    
    private func saveChanges() async {
        saveProgress = .resizeDiskImage(0)
        saveError = nil
        isSaving = true
        
        let binaryCoder = BinaryMetadataCoder()
        let data = binaryCoder.encode(launchOptions)
        
        let successfullyAuthorized = instance.bundlePath.url.startAccessingSecurityScopedResource()
        defer {
            if successfullyAuthorized {
                instance.bundlePath.url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let currentLaunchOptions = launchOptions
            
            if initialLaunchOptions.storageGb != currentLaunchOptions.storageGb {
                for try await percentage in diskUtilClient.resizeDiskImage(at: instance.bundlePath.diskImageURL, toSizeInGiB: launchOptions.storageGb) {
                    print("Progress: \(percentage)%")
                    saveProgress = .resizeDiskImage(percentage)
                }
            }
            
            saveProgress = .saveMetadata
            
            let metaDataURL = instance.bundlePath.metaDataURL
            
            try await Task.detached(name: "Save Launch Option changes", priority: .userInitiated) {
                if initialLaunchOptions != currentLaunchOptions {
                    try data.write(to: metaDataURL)
                    print("Successfully saved launch options: \(currentLaunchOptions)")
                } else {
                    print("Launch options were unchanged")
                }
            }.value
        } catch {
            print("Failed to save launch options: \(error)")
            saveError = error
        }
        
        isSaving = false
        
        try? await Task.sleep(for: .seconds(0.1))
        
        dismissWindow()
    }
}
