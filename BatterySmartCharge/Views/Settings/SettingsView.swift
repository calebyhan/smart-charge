import SwiftUI

struct SettingsView: View {
    @StateObject var settings: UserSettings
    
    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            TimeRulesView(settings: settings)
                .tabItem {
                    Label("Time Rules", systemImage: "clock")
                }
            
            PowerDrawSettingsView(settings: settings)
                .tabItem {
                    Label("Power", systemImage: "bolt")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings: UserSettings
    
    var body: some View {
        Form {
            Section(header: Text("Charging Thresholds")) {
                VStack(alignment: .leading) {
                    Text("Stop charging at: \(settings.maxThreshold)%")
                    Slider(value: Binding(
                        get: { Double(settings.maxThreshold) },
                        set: { settings.maxThreshold = Int($0) }
                    ), in: 50...100, step: 1) {
                        Text("Max Limit")
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("Start charging at: \(settings.minThreshold)%")
                    Slider(value: Binding(
                        get: { Double(settings.minThreshold) },
                        set: { settings.minThreshold = Int($0) }
                    ), in: 5...50, step: 1) {
                        Text("Min Limit")
                    }
                }
            }
            
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        LaunchHelper.setLaunchAtLogin(newValue)
                    }
                ))

                Picker("Temperature Unit", selection: $settings.useFahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.batteryblock.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.green)

            Text("Smart Charge")
                .font(.title)

            Text("Version 1.0.0")
                .font(.caption)

            Text("Intelligent battery management for macOS.")
                .multilineTextAlignment(.center)
                .padding()

            Link(destination: URL(string: "https://github.com/calebyhan/smart-charge")!) {
                HStack {
                    Image(systemName: "link")
                    Text("GitHub")
                }
            }

            Spacer()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Quit Smart Charge")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
    }
}
