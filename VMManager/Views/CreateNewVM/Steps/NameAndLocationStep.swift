import SwiftUI

struct NameAndLocationStep: View {
    @Binding private var vmName: String
    @Binding private var nameError: String?
    @Binding private var filePickerState: FilePickerState
    @Binding private var isFilePickerPresented: Bool
    
    private let bundlePath: VmBundlePath
    private let validateName: () -> Void
    
    init(vmName: Binding<String>, nameError: Binding<String?>, filePickerState: Binding<FilePickerState>, isFilePickerPresented: Binding<Bool>, bundlePath: VmBundlePath, validateName: @escaping () -> Void) {
        self._vmName = vmName
        self._nameError = nameError
        self._filePickerState = filePickerState
        self._isFilePickerPresented = isFilePickerPresented
        self.bundlePath = bundlePath
        self.validateName = validateName
    }
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "textformat.abc")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue.gradient)
                
                Text("Name Your Virtual Machine")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Choose a name and storage location for your VM")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 20)
            
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Virtual Machine Name", systemImage: "textformat")
                            .font(.headline)
                        
                        Spacer()
                    }
                    
                    TextField("Enter VM name", text: $vmName)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .frame(height: 44)
                        .onChange(of: vmName) {
                            validateName()
                        }
                    
                    if let error = nameError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("This will be the display name for your VM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Storage Location", systemImage: "internaldrive")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button {
                            filePickerState = .selectingPath
                            isFilePickerPresented = true
                        } label: {
                            Label("Change", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VM Bundle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        HStack {
                            Image(systemName: "doc.badge.gearshape")
                                .foregroundStyle(.secondary)
                            
                            // TODO: - (maybe) include backslashes before spaces
                            Text(bundlePath.url.path(percentEncoded: false))
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer(minLength: 0)
                            
                            Button {
                                NSPasteboard.general.setString(bundlePath.url.path(percentEncoded: false), forType: .string)
                            } label: {
                                Label("Copy", systemImage: "clipboard")
                            }
                        }
                        .help(bundlePath.url.path(percentEncoded: false))
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: 500)
        }
        .padding(40)
    }
}
