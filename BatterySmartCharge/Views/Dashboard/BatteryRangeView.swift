import SwiftUI

struct BatteryRangeView: View {
    let currentPercent: Int
    let minThreshold: Int
    let maxThreshold: Int
    let targetMin: Int
    let targetMax: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Battery Range")
                .font(.caption)
                .foregroundColor(.secondary)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                    
                    // Available Range (Min to Max) - only show if not 0-100
                    if minThreshold > 0 || maxThreshold < 100 {
                        Rectangle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(
                                width: widthForRange(min: minThreshold, max: maxThreshold, totalWidth: geometry.size.width),
                                height: geometry.size.height
                            )
                            .offset(x: offsetForValue(minThreshold, totalWidth: geometry.size.width))
                    }
                    
                    // Target Range (TargetMin to TargetMax)
                    Rectangle()
                        .fill(Color.green.opacity(0.3))
                        .frame(
                            width: widthForRange(min: targetMin, max: targetMax, totalWidth: geometry.size.width),
                            height: geometry.size.height
                        )
                        .offset(x: offsetForValue(targetMin, totalWidth: geometry.size.width))
                    
                    // Current Level Indicator
                    Capsule()
                        .fill(colorForLevel(currentPercent))
                        .frame(width: 4, height: geometry.size.height + 6)
                        .offset(x: offsetForValue(currentPercent, totalWidth: geometry.size.width))
                        .shadow(radius: 1)
                }
            }
            .frame(height: 20)
            
            HStack {
                Text("0%")
                Spacer()
                Text("Target: \(targetMin)%-\(targetMax)%")
                    .foregroundColor(.green)
                    .font(.caption2)
                Spacer()
                Text("100%")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private func widthForRange(min: Int, max: Int, totalWidth: CGFloat) -> CGFloat {
        let range = CGFloat(max - min)
        return (range / 100.0) * totalWidth
    }
    
    private func offsetForValue(_ value: Int, totalWidth: CGFloat) -> CGFloat {
        return (CGFloat(value) / 100.0) * totalWidth
    }
    
    private func colorForLevel(_ level: Int) -> Color {
        if level < minThreshold { return .red }
        if level > maxThreshold { return .orange }
        if level >= targetMin && level <= targetMax { return .green }
        return .blue
    }
}

struct BatteryRangeView_Previews: PreviewProvider {
    static var previews: some View {
        BatteryRangeView(
            currentPercent: 65,
            minThreshold: 20,
            maxThreshold: 90,
            targetMin: 60,
            targetMax: 70
        )
        .padding()
        .frame(width: 300)
    }
}
