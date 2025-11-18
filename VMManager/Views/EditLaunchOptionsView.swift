import SwiftUI
import SwiftData
import Virtualization

struct EditLaunchOptionsView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.modelContext) private var modelContext
    
    private let instance: VMInstance
    private let diskUtilClient = DiskUtilityClient()
    @State private var launchOptions: LaunchOptions
    @State private var spaceAvailableInGb: UInt
    
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
            self._launchOptions = State(initialValue: try binaryCoder.decodeLaunchOptions(from: data))
        } catch {
            print("unable to load launch options from \(instance.bundlePath.metaDataURL): \(error)")
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
    
    private func saveChanges() async {
        let binaryCoder = BinaryMetadataCoder()
        let data = binaryCoder.encode(launchOptions)
        
        let successfullyAuthorized = instance.bundlePath.url.startAccessingSecurityScopedResource()
        defer {
            if successfullyAuthorized {
                instance.bundlePath.url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            for try await progress in diskUtilClient.resizeDiskImage(at: instance.bundlePath.diskImageURL, toSizeInGiB: launchOptions.storageGb) {
                print("Progress: \(progress)%")
                // TODO: - Add UI that alerts user to progress
            }
            
            try data.write(to: instance.bundlePath.metaDataURL)
            print("✅ Successfully saved launch options: \(launchOptions)")
            // TODO: - Change size of filesystem using diskutil (see `man diskutil` in terminal for more info, specifically, `diskutil image resize -s <sizeInGb>GiB <urlOfImage>`)
        } catch {
            print("❌ Failed to save launch options: \(error)")
            // TODO: Show error alert to user
        }
        
        dismissWindow()
    }
}
