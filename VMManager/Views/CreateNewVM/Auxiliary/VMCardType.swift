import SwiftUI

struct VMTypeCard: View {
    enum Icon {
        case systemName(String)
        case assetName(String)
    }
    
    private let icon: Icon
    private let title: String
    private let description: String
    private let isSelected: Bool
    private let isAvailable: Bool
    private let action: () -> Void
    
    init(image: String, title: String, description: String, isSelected: Bool, isAvailable: Bool, action: @escaping () -> Void) {
        self.icon = .assetName(image)
        self.title = title
        self.description = description
        self.isSelected = isSelected
        self.isAvailable = isAvailable
        self.action = action
    }
    
    init(systemImage: String, title: String, description: String, isSelected: Bool, isAvailable: Bool, action: @escaping () -> Void) {
        self.icon = .systemName(systemImage)
        self.title = title
        self.description = description
        self.isSelected = isSelected
        self.isAvailable = isAvailable
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundStyle(isSelected ? Color.accentColor.gradient : (isAvailable ? Color.primary.gradient : Color.secondary.gradient))
                
                VStack(spacing: 8) {
                    HStack {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        if !isAvailable {
                            Text("Soon")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .focusEffectDisabled()
    }
    
    private var image: Image {
        switch icon {
        case let .assetName(name):
            Image(name)
        case let .systemName(name):
            Image(systemName: name)
        }
    }
}
