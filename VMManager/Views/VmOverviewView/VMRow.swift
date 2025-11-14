import SwiftUI

struct VMRow: View {
    private let instance: VMInstance
    private let isSelected: Bool
    private let onLaunch: (Bool) -> Void
    private let onSelect: () -> Void
    private let onDelete: () -> Void
    private let onRelink: () -> Void
    private let onEdit: () -> Void
    
    private var canBeLaunched: Bool {
        instance.createdAt != nil && instance.isLinked
    }
    
    @State private var lastTap: Date?
    @State private var isHovering = false
    
    init(instance: VMInstance, isSelected: Bool, onLaunch: @escaping (Bool) -> Void, onSelect: @escaping () -> Void, onDelete: @escaping () -> Void, onRelink: @escaping () -> Void, onEdit: @escaping () -> Void) {
        self.instance = instance
        self.isSelected = isSelected
        self.onLaunch = onLaunch
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onRelink = onRelink
        self.onEdit = onEdit
    }
    
    var body: some View {
        HStack(spacing: 16) {
            if instance.createdAt == nil {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: instance.isLinked ? "laptopcomputer" : "laptopcomputer.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(instance.isLinked ? .primary : .secondary)
            }
            
            infoSection
            
            Spacer()
            
            actions
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            
            if let lastTap, lastTap.timeIntervalSinceNow > -0.3 {
                launch(inRecoveryMode: false)
            }
            
            lastTap = .now
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(instance.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text("macOS")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                
                if !instance.isLinked {
                    Label("Unlinked", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            
            metadata
        }
    }
    
    private var metadata: some View {
        HStack(spacing: 12) { // TODO: - Store metadata in bundle so that if you create a new VMInstance from an existing bundle or relink, you have all the metadata
            Label {
                Text(instance.bundlePath.url.standardizedFileURL.path(percentEncoded: false))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "folder")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            if let created = instance.createdAt {
                Label {
                    Text("Created \(created, format: .relative(presentation: .named))")
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Label {
                if let lastRan = instance.lastRanAt {
                    Text(lastRan, style: .relative)
                } else {
                    Text("Never run")
                }
            } icon: {
                Image(systemName: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
    
    private var actions: some View {
        HStack(spacing: 12) {
            if !instance.isLinked {
                Button {
                    onRelink()
                } label: {
                    Label("Relink", systemImage: "link.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Relink to VM bundle")
            }
            
            Button {
                launch(inRecoveryMode: false)
            } label: {
                Label("Launch", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!canBeLaunched)
            
            contextMenu
        }
    }
    
    private var contextMenu: some View {
        Menu {
            Button {
                launch(inRecoveryMode: false)
            } label: {
                Label("Launch", systemImage: "play")
            }
            .disabled(!canBeLaunched)
            
            Button {
                launch(inRecoveryMode: true)
            } label: {
                Label("Launch in Recovery Mode", systemImage: "bandage")
            }
            .disabled(!canBeLaunched)
            
            Divider()
            
            Button {
                NSWorkspace.shared.selectFile(
                    instance.bundlePath.url.path(percentEncoded: false),
                    inFileViewerRootedAtPath: ""
                )
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            
            if !instance.isLinked {
                Button {
                    onRelink()
                } label: {
                    Label("Relink Bundle", systemImage: "link.badge.plus")
                }
            }
            
            Divider()
            
            Button {
                onEdit()
            } label: {
                Label("Edit Launch Options", systemImage: "slider.horizontal.3")
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18))
        }
        .menuStyle(.borderlessButton)
        .help("More options")
    }
    
    private func launch(inRecoveryMode: Bool) {
        guard canBeLaunched else { return }
        onLaunch(inRecoveryMode)
    }
}
