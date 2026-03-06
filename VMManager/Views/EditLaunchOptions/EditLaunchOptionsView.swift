import SwiftUI
import SwiftData
import Virtualization

struct EditLaunchOptionsView: View {
    @State private var model: EditLaunchOptionsViewModel
    
    init(instance: VMInstance) {
        // TODO: - Determine if State(initialValue:) in initializer is still bad practice
        self._model = State(initialValue: EditLaunchOptionsViewModel(instance: instance))
    }
    
    var body: some View {
        _EditLaunchOptionsView(model: model)
    }
}

fileprivate struct _EditLaunchOptionsView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.modelContext) private var modelContext
    
    private let model: EditLaunchOptionsViewModel
    
    init(model: EditLaunchOptionsViewModel) {
        self.model = model
    }
    
    var body: some View {
        let bindable = Bindable(model)
        
        TabView {
            Tab {
                VStack(spacing: 0) {
                    header
                    
                    Divider()
                    
                    ResourcesStep(
                        launchOptions: bindable.launchOptions,
                        spaceAvailableInGb: model.spaceAvailableInGb
                    )
                    
                    Divider()
                    
                    footer
                }
            } label: {
                Label("Resources", systemImage: "cpu")
            }
            
            Tab {
                VStack(spacing: 0) {
                    header
                    
                    Divider()
                    
                    SharingStep(launchOptions: bindable.launchOptions)
                    
                    Divider()
                    
                    footer
                }
            } label: {
                Label("Sharing", systemImage: "rectangle.2.swap")
            }
        }
        .sheet(isPresented: bindable.isSaving) {
            if let saveProgress = model.saveProgress {
                savingProgressSheet(progress: saveProgress)
            } else {
                Color.clear
                    .onAppear {
                        model.isSaving = false
                    }
            }
        }
        .alert("Save Failed", isPresented: Binding(
            get: { model.saveError != nil },
            set: { if !$0 { model.saveError = nil } }
        )) {
            Button("OK") {
                model.saveError = nil
            }
        } message: {
            if let error = model.saveError {
                Text(error.localizedDescription)
            }
        }
        .onChange(of: model.isSaving) {
            print(model.isSaving)
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
                    
                    Text(model.displayName)
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
                    if await model.saveChanges() {
                        try? await Task.sleep(for: .seconds(0.1))
                        
                        dismissWindow()
                    }
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
    
    private func savingProgressSheet(progress: VMResourceUpdateProgress) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                switch progress {
                case .validating:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                case let .resizingDisk(percentage):
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
                case .updatingMetadata:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                case .complete:
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 58, height: 58)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            
            VStack(spacing: 8) {
                switch progress {
                case .validating:
                    Text("Validating")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Ensuring bells and whistles are in place...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case let .resizingDisk(percentage):
                    Text("Resizing Disk Image")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(percentage)% complete")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .updatingMetadata:
                    Text("Saving Changes")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Preparing to save...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .complete:
                    Text("Complete")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
            
            if progress == .complete {
                Button("Done") {
                    model.isSaving = false
                    
                    Task {
                        try? await Task.sleep(for: .seconds(0.1))
                        
                        dismissWindow()
                    }
                }
            }
        }
        .padding(40)
        .frame(width: 450)
        .interactiveDismissDisabled()
    }
}

#Preview {
    @Previewable @State var model = EditLaunchOptionsViewModel(lifecycleService: VMLifecycleService(), bundlePath: VMBundlePath(containerURL: URL(filePath: "/Users/jman"), bundleName: "vm"), displayName: "VM", initialLaunchOptions: LaunchOptions(cpuCores: 2, memoryGb: 16, storageGb: 64), spaceAvailableInGb: 100)
    
    _EditLaunchOptionsView(model: model)
}
