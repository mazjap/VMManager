import SwiftUI

struct ReviewRow: View {
    let label: String
    let value: String
    let icon: String
    var truncate: Bool = false
    
    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(truncate ? 1 : nil)
                .truncationMode(.middle)
        }
    }
}
