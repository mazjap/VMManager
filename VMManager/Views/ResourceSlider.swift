import SwiftUI

struct ResourceSlider<V: BinaryInteger>: View {
    let icon: String
    let title: String
    @Binding var value: V
    let range: ClosedRange<V>
    let color: Color
    let formatter: (V) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                
                Spacer()
                
                Text(formatter(value))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            
            Slider(value: Binding(
                get: { Double(value) },
                set: { value = V($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            .tint(color)
            
            HStack {
                Text(formatter(range.lowerBound))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(formatter(range.upperBound))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
