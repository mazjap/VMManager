import SwiftUI

struct CreateNewVMFooter: View {
    @Binding private var currentStep: VMCreationStep
    
    private let canProceedFromCurrentStep: Bool
    private let onCancel: () -> Void
    private let onCreateAndInstall: () -> Void
    
    init(currentStep: Binding<VMCreationStep>, canProceedFromCurrentStep: Bool, onCancel: @escaping () -> Void, onCreateAndInstall: @escaping () -> Void) {
        self._currentStep = currentStep
        self.canProceedFromCurrentStep = canProceedFromCurrentStep
        self.onCancel = onCancel
        self.onCreateAndInstall = onCreateAndInstall
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                onCancel()
            } label: {
                Text("Cancel")
                    .frame(minWidth: 80)
            }
            .buttonStyle(.bordered)
            .tint(Color(nsColor: NSColor.systemRed))
            
            Spacer()
            
            if currentStep != .vmType {
                Button {
                    if let previousStep = VMCreationStep(rawValue: currentStep.rawValue - 1) {
                        currentStep = previousStep
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        
                        Text("Back")
                    }
                    .frame(minWidth: 80)
                }
            }
            
            if currentStep == .review {
                Button {
                    onCreateAndInstall()
                } label: {
                    HStack {
                        Text("Create & Install")
                        
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceedFromCurrentStep)
            } else {
                Button {
                    if let nextStep = VMCreationStep(rawValue: currentStep.rawValue + 1) {
                        currentStep = nextStep
                    }
                } label: {
                    HStack {
                        Text("Continue")
                        
                        Image(systemName: "chevron.right")
                    }
                    .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canProceedFromCurrentStep)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
