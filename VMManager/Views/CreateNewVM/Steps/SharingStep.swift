import SwiftUI
import Virtualization

struct SharingStep: View {
    @Binding private var launchOptions: LaunchOptions
    
    init(launchOptions: Binding<LaunchOptions>) {
        self._launchOptions = launchOptions
    }
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.2.swap")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue.gradient)
                
                Text("Configure Sharing")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Determine what should be shared between host and guest Virtual Machine")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 20)
            
            VStack(spacing: 24) {
                Toggle("Share clipboard", isOn: $launchOptions.sharesClipboard)
            }
            .frame(maxWidth: 500)
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("[This package](https://github.com/utmapp/vd_agent/releases/latest) must be installed in the guest VM to share the clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
    }
}
