import SwiftUI

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    var color: Color = .primary
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
