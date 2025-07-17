import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ScannerViewModel()
    @State private var selectedTab = 0
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // *** UPDATED: Further reduced vertical padding and spacing for a tighter layout. ***
                VStack(spacing: 4) {
                    Text("Anchor ID: \(viewModel.anchorId)")
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Text(viewModel.statusMessage).font(.headline).padding(.horizontal)
                    
                    if viewModel.isJobScanning {
                        ProgressView(value: viewModel.scanProgress)
                            .progressViewStyle(.linear)
                            .padding(.horizontal)
                    }
                    
                }
                .padding(.horizontal)
                .padding(.vertical, 8) // Reduced vertical padding
                .frame(maxWidth: .infinity).background(Color(UIColor.systemGray6))
                
                TabView(selection: $selectedTab) {
                    matchedTagsView
                        .tabItem { Label("Matched Tags", systemImage: "checkmark.circle.fill") }
                        .tag(0)
                    
                    allDevicesDebugView
                        .tabItem { Label("All Devices (Debug)", systemImage: "ladybug.fill") }
                        .tag(1)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("BadgeIt! Sense Tag Reader")
                        // *** UPDATED: Increased base font size for iPhone. ***
                        .font(horizontalSizeClass == .regular ? .title2 : .title3)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                
                if selectedTab == 1 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            viewModel.startDebugScan()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.isJobScanning || viewModel.isDebugScanning)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    @ViewBuilder
    private var matchedTagsView: some View {
        if viewModel.isJobScanning {
            if viewModel.matchedTags.isEmpty {
                VStack {
                    Spacer()
                    Text("Scanning for tags...").font(.title2).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                list(of: viewModel.matchedTags)
            }
        } else {
            VStack {
                Spacer()
                Text("Waiting for scan job...").font(.title2).foregroundColor(.secondary)
                Spacer()
            }
        }
    }
    
    private func list(of tags: [DiscoveredTag]) -> some View {
        List(tags) { tag in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // *** UPDATED: Removed the Velavu ID (tag.id) from the display. ***
                    Text(tag.uuid).font(.title2).fontWeight(.bold)
                    Text("Last seen: \(tag.lastSeenFormatted)").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(tag.rssi) dBm").font(.system(.title, design: .monospaced)).fontWeight(.medium).foregroundColor(rssiColor(for: tag.rssi))
            }.padding(.vertical, 8)
        }
    }
    
    private var allDevicesDebugView: some View {
        List(viewModel.allDiscoveredDevices) { device in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(device.name).font(.headline)
                    Spacer()
                    Text("\(device.rssi) dBm").foregroundColor(rssiColor(for: device.rssi))
                }
                Text("Last Seen: \(device.lastSeenFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(device.advertisementDetails)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }.padding(.vertical, 6)
        }
    }
    
    private func rssiColor(for rssi: Int) -> Color {
        if rssi > -65 { return .green }
        else if rssi > -80 { return .orange }
        else { return .red }
    }
}
