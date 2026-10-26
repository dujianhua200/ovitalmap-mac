import SwiftUI

// MARK: - Toolbar

struct ToolbarView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Tile source picker
            Picker("Tile Source", selection: $vm.activeTileSource) {
                ForEach(TileSource.allCases) { src in
                    Text(src.displayName).tag(src)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Divider()

            // Zoom buttons
            Button { vm.zoomLevel = min(18, vm.zoomLevel + 1) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")

            Button { vm.zoomLevel = max(3, vm.zoomLevel - 1) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")

            Text("\(Int(vm.zoomLevel))")
                .frame(width: 24, alignment: .center)
                .font(.caption)

            Divider()

            // GPX import
            Button("Import GPX…") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                let panel = NSOpenPanel()
                panel.allowedFileTypes = ["gpx"]
                panel.allowsMultipleSelection = true
                if panel.runModal() == .OK {
                    for url in panel.urls {
                        if let data = try? Data(contentsOf: url) {
                            vm.importGPX(data)
                        }
                    }
                }
            }

            // Clear GPX
            Button("Clear GPX", action: vm.clearAllGPX)
                .disabled(vm.tracks.isEmpty && vm.routes.isEmpty)

            Divider()

            // Fence mode
            Button(vm.isPlacingFence ? "Finish Fence" : "Draw Fence") {
                if vm.isPlacingFence {
                    vm.finishFencePlacement()
                } else {
                    let name = "Fence \(vm.fences.count + 1)"
                    vm.startFencePlacement(name: name)
                }
            }
            .disabled(vm.isPlacingFence && vm.fenceDraftVertices.count < 3)

            Button("Clear Fences", action: vm.clearAllFences)
                .disabled(vm.fences.isEmpty)

            Spacer()

            // Zoom label
            Text("Z \(Int(vm.zoomLevel))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
