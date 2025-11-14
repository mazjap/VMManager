import SwiftUI

struct StepIndicator: View {
    let step: VMCreationStep
    let currentStep: VMCreationStep
    let isCompleted: Bool
    
    private var isActive: Bool {
        step == currentStep
    }
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.accentColor : (isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.2)))
                    .frame(width: 32, height: 32)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: step.icon)
                        .font(.caption)
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                }
            }
            
            Text(step.title)
                .font(.caption2)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
