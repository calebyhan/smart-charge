import SwiftUI

struct PowerDrawSettingsView: View {
    @ObservedObject var settings: UserSettings
    
    var body: some View {
        Form {
            Section(header: Text("Usage Definitions"), footer: Text("Smart Charge adjusts its behavior based on how much power your Mac is using.")) {
                
                VStack(alignment: .leading) {
                    Text("Light Usage: < \(Int(settings.lightUsageThreshold))W")
                    Slider(value: $settings.lightUsageThreshold, in: 5...30, step: 1) {
                        Text("Light Threshold")
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("Heavy Usage: > \(Int(settings.heavyUsageThreshold))W")
                    Slider(value: $settings.heavyUsageThreshold, in: 20...100, step: 1) {
                        Text("Heavy Threshold")
                    }
                }
            }
            
            Section(header: Text("Response Strategy")) {
                // Future: Allow customizing actions for each level
                Label("Ideally, keep Light Usage below 15W for best trickle charging efficiency.", systemImage: "lightbulb")
                    .font(.caption)
            }
        }
        .padding()
    }
}
