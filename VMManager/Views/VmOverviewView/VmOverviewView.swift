import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct VmLaunchParameters: Hashable, Codable {
    var instanceId: PersistentIdentifier
    var isInRecoveryMode: Bool
}

enum VMSortOrder {
    case name
    case lastRun
    case created
}

struct VMStats {
    let totalCount: Int
    let recentlyUsedCount: Int
    let unlinkedCount: Int
}

enum VmOverviewViewFilePickerState {
    case relinkingInstance(VMInstance)
    case importingExistingVirtualMachine
}

struct VmOverviewView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    
    private let instances: [VMInstance]
    
    @State private var searchText = ""
    @State private var sortOrder: VMSortOrder = .lastRun
    @State private var selectedInstance: VMInstance?
    
    @State private var filePickerState: VmOverviewViewFilePickerState = .importingExistingVirtualMachine
    @State private var isShowingFileSelector = false
    @State private var isShowingNewVMAlert = false
    
    @State private var instanceToEditLaunchOptions: VMInstance?
    @State private var isShowingLaunchOptionsEditor = false
    
    private var filteredInstances: [VMInstance] {
        let filtered = instances.filter { instance in
            searchText.isEmpty || instance.name.localizedCaseInsensitiveContains(searchText)
        }
        
        return filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .name:
                return lhs.name < rhs.name
            case .lastRun:
                return (lhs.lastRanAt ?? .distantPast) > (rhs.lastRanAt ?? .distantPast)
            case .created:
                return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }
        }
    }
    
    private var stats: VMStats {
        VMStats(
            totalCount: instances.count,
            recentlyUsedCount: instances.filter {
                guard let lastRan = $0.lastRanAt else { return false }
                return lastRan.timeIntervalSinceNow > -7 * 24 * 60 * 60 // Last 7 days
            }.count,
            unlinkedCount: instances.filter { !$0.isLinked }.count
        )
    }
    
    init(instances: [VMInstance]) {
        self.instances = instances
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !instances.isEmpty {
                statsHeader
            }
            
            Divider()
            
            if instances.isEmpty {
                emptyState
            } else {
                vmList
            }
        }
        .searchable(text: $searchText, prompt: "Search VMs")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        Label("Name", systemImage: "textformat.abc")
                            .tag(VMSortOrder.name)
                        Label("Last Run", systemImage: "clock")
                            .tag(VMSortOrder.lastRun)
                        Label("Created", systemImage: "calendar")
                            .tag(VMSortOrder.created)
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort virtual machines")
                
                Button {
                    isShowingNewVMAlert = true
                } label: {
                    Label("New Virtual Machine", systemImage: "plus")
                }
                .help("Create a new virtual machine")
            }
        }
        .fileImporter(
            isPresented: $isShowingFileSelector,
            allowedContentTypes: [.bundle, .package],
            allowsMultipleSelection: false,
            onCompletion: { result in
                defer { filePickerState = .importingExistingVirtualMachine }
                
                guard case let .success(success) = result,
                      let url = success.first
                else { return }
                
                switch filePickerState {
                case let .relinkingInstance(relinkingInstance):
                    relink(instance: relinkingInstance, withPath: url)
                case .importingExistingVirtualMachine:
                    do {
                        try importExistingInstance(fromPath: url)
                    } catch {
                        fatalError("Bad things happened while importing VM from filesystem: \(error)")
                    }
                }
                
                
            }, onCancellation: {
                filePickerState = .importingExistingVirtualMachine
            }
        )
        .alert("New Virtual Machine", isPresented: $isShowingNewVMAlert) {
            Button("Import Existing") {
                isShowingFileSelector = true
            }
            
            Button("Create New") {
                openWindow(id: WindowId.newVMOptions.rawValue)
            }
            
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            updateLinkStatuses()
        }
    }
    
    // MARK: - Stats Header
    
    private var statsHeader: some View {
        HStack(spacing: 24) {
            StatItem(
                value: "\(stats.totalCount)",
                label: stats.totalCount == 1 ? "Virtual Machine" : "Virtual Machines",
                icon: "laptopcomputer"
            )
            
            if stats.recentlyUsedCount > 0 {
                Divider()
                    .frame(height: 20)
                
                StatItem(
                    value: "\(stats.recentlyUsedCount)",
                    label: "Used This Week",
                    icon: "clock.arrow.circlepath"
                )
            }
            
            if stats.unlinkedCount > 0 {
                Divider()
                    .frame(height: 20)
                
                StatItem(
                    value: "\(stats.unlinkedCount)",
                    label: stats.unlinkedCount == 1 ? "Unlinked" : "Unlinked",
                    icon: "exclamationmark.triangle",
                    color: .orange
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - VM List
    
    private var vmList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(filteredInstances) { instance in
                    VMRow(
                        instance: instance,
                        isSelected: selectedInstance?.id == instance.id,
                        onLaunch: { isInRecoveryMode in
                            updateLinkStatus(for: instance)
                            
                            if instance.isLinked {
                                launchVM(instance, isInRecoveryMode: isInRecoveryMode)
                            }
                        },
                        onSelect: {
                            selectedInstance = instance
                        },
                        onDelete: {
                            // TODO: - Delete bundle on filesystem when VMInstance is deleted
                            deleteVM(instance)
                        },
                        onRelink: {
                            filePickerState = .relinkingInstance(instance)
                            isShowingFileSelector = true
                        },
                        onEdit: {
                            openWindow(id: WindowId.editLaunchOptions.rawValue, value: instance.id)
                        }
                    )
                }
            }
            .padding(12)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Virtual Machines", systemImage: "laptopcomputer.slash")
        } description: {
            Text("Create your first macOS virtual machine to get started")
        } actions: {
            Button {
                openWindow(id: WindowId.newVMOptions.rawValue)
            } label: {
                Label("Create Virtual Machine", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    // MARK: - Actions
    
    // TODO: - Add more launch options
    private func launchVM(_ instance: VMInstance, isInRecoveryMode: Bool) {
        openWindow(id: WindowId.virtualMachine.rawValue, value: VmLaunchParameters(instanceId: instance.id, isInRecoveryMode: isInRecoveryMode))
        instance.lastRanAt = Date()
        try? modelContext.save()
    }
    
    private func deleteVM(_ instance: VMInstance) {
        modelContext.delete(instance)
        try? modelContext.save()
    }
    
    private func relink(instance: VMInstance, withPath path: URL) {
        let instanceManager = InstanceManager(instance: instance, context: modelContext, isInRecoveryMode: false)
        let vmBundlePath = try! VmBundlePath(bundleURL: path)
        instanceManager.bundlePath = vmBundlePath
        updateLinkStatus(for: instance)
    }
    
    private func importExistingInstance(fromPath path: URL) throws {
        if let existingInstance = instances.first(where: { $0.bundlePath.url.standardizedFileURL == path.standardizedFileURL }) {
            selectedInstance = existingInstance
            return
        }
        
        let bundlePath = try VmBundlePath(bundleURL: path)
        
        let successfullyAuthorized = path.startAccessingSecurityScopedResource()
        defer {
            if successfullyAuthorized {
                path.stopAccessingSecurityScopedResource()
            }
        }
        
        let instance = InstanceManager(vmBundlePath: bundlePath, context: modelContext, isInRecoveryMode: false)
        instance.createdAt = .now
        updateLinkStatus(for: instance.instance)
        selectedInstance = instance.instance
    }
    
    private func updateLinkStatuses() {
        for instance in instances {
            updateLinkStatus(for: instance, shouldSave: false)
        }
        
        try? modelContext.save()
    }
    
    private func updateLinkStatus(for instance: VMInstance, shouldSave: Bool = true) {
        do {
            let url = try instance.getSecurityScopedURL()
            let path = try VmBundlePath(bundleURL: url)
            
            instance.isLinked = FileManager.default.fileExists(atPath: path.url.path(percentEncoded: false))
        } catch {
            instance.isLinked = false
        }
        
        if shouldSave {
            try? modelContext.save()
        }
    }
}

#Preview {
    VmOverviewView(instances: [])
        .frame(width: 900, height: 600)
}


/// SwiftData's Query macro causes self to not be inspectable in LLDB which is
/// super annoying. I created this container to do the query stuff and then pass the
/// array to `VmOverviewView` so that `VmOverviewView` can be debugged.
struct VmOverviewViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VMInstance.createdAt) private var instances: [VMInstance]
    
    var body: some View {
        VmOverviewView(instances: instances)
    }
}
