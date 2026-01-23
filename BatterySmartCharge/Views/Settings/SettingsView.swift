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

struct RangeSlider: View {
    @Binding var minValue: Int
    @Binding var maxValue: Int
    let range: ClosedRange<Int>

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let minPos = positionFor(value: minValue, in: width)
            let maxPos = positionFor(value: maxValue, in: width)

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 6)

                // Selected range
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: maxPos - minPos, height: 6)
                    .offset(x: minPos)

                // Min handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(x: minPos - 10)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newValue = valueFor(position: value.location.x, in: width)
                                minValue = min(newValue, maxValue - 5)
                            }
                    )

                // Max handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(x: maxPos - 10)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newValue = valueFor(position: value.location.x, in: width)
                                maxValue = max(newValue, minValue + 5)
                            }
                    )
            }
        }
        .frame(height: 20)
    }

    private func positionFor(value: Int, in width: CGFloat) -> CGFloat {
        let percent = CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
        return percent * width
    }

    private func valueFor(position: CGFloat, in width: CGFloat) -> Int {
        let percent = max(0, min(1, position / width))
        return range.lowerBound + Int(percent * CGFloat(range.upperBound - range.lowerBound))
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings: UserSettings

    var body: some View {
        Form {
            Section(header: Text("Charging Thresholds")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Start: \(settings.minThreshold)%")
                        Spacer()
                        Text("Stop: \(settings.maxThreshold)%")
                    }
                    .font(.subheadline)

                    RangeSlider(
                        minValue: $settings.minThreshold,
                        maxValue: $settings.maxThreshold,
                        range: 5...100
                    )
                    .padding(.horizontal, 10)
                }
                .padding(.vertical, 8)
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

            Text("Version 1.0.3")
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
