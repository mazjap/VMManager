import SwiftUI

struct CreateNewVMHeader: View {
    private let currentStep: VMCreationStep
    
    init(currentStep: VMCreationStep) {
        self.currentStep = currentStep
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue.gradient)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Virtual Machine")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Step \(currentStep.rawValue + 1) of \(VMCreationStep.allCases.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            HStack(spacing: 4) {
                ForEach(VMCreationStep.allCases, id: \.self) { step in
                    StepIndicator(
                        step: step,
                        currentStep: currentStep,
                        isCompleted: step.rawValue < currentStep.rawValue
                    )
                    
                    if step != VMCreationStep.allCases.last {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
