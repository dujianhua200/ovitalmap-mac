import SwiftUI

// MARK: - Side Panel (layers, readout, fences, beacons)

struct SidePanelView: View {
    @ObservedObject var vm: AppViewModel

    @State private var selectedTab: PanelTab = .readout

    enum PanelTab: String, CaseIterable, Identifiable {
        case readout = "Readout"
        case layers = "Layers"
        case fences = "Fences"
        case beacons = "Beacons"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack {
                ForEach(PanelTab.allCases) { tab in
                    Button(tab.rawValue) { selectedTab = tab }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.25) : .clear)
                        .cornerRadius(6)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // Tab content
            ScrollView {
                switch selectedTab {
                case .readout:  readoutContent
                case .layers:   layersContent
                case .fences:   fencesContent
                case .beacons:  beaconsContent
                }
            }
            .padding(8)
        }
        .frame(width: 280)
    }

    // MARK: Readout

    private var readoutContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coordinate Readout").font(.headline)

            Text(vm.coordinateReadout)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

            // Status alerts
            if let msg = vm.alertMessage {
                HStack {
                    Circle().fill(alertColor(vm.alertSeverity)).frame(width: 8, height: 8)
                    Text(msg)
                        .font(.caption)
                        .lineLimit(3)
                }
                .padding(6)
                .background(alertColor(vm.alertSeverity).opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 6))
            }

            // Status: click to read
            Text("Click on the map to read the coordinate at that point.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            // GPS position (simulated)
            HStack {
                Image(systemName: "location")
                Text("Center")
                Text(String(format: "%.4f, %.4f", vm.mapCenter.latitude, vm.mapCenter.longitude))
                    .font(.caption2)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func alertColor(_ sev: AlertSeverity) -> Color {
        switch sev {
        case .info:    return .blue
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }

    // MARK: Layers

    private var layersContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layers").font(.headline)

            // Tracks
            if !vm.tracks.isEmpty {
                sectionHeader("Tracks", count: vm.tracks.count)
                ForEach(vm.tracks) { t in
                    HStack {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        Text(t.name ?? "Untitled Track").lineLimit(1)
                        Text("\(t.segments.count) seg(s)")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .font(.caption)
                }
            }

            // Routes
            if !vm.routes.isEmpty {
                sectionHeader("Routes", count: vm.routes.count)
                ForEach(vm.routes) { r in
                    HStack {
                        Image(systemName: "arrow.triangle.turnup.right.diamond")
                        Text(r.name ?? "Route").lineLimit(1)
                        Spacer()
                    }
                    .font(.caption)
                }
            }

            // Point marks
            if !vm.pointMarks.isEmpty {
                sectionHeader("Point Marks", count: vm.pointMarks.count)
                ForEach(vm.pointMarks) { p in
                    HStack {
                        Image(systemName: "mappin")
                        Text(p.label ?? "Point").lineLimit(1)
                        Text(String(format: "%.4f", p.latitude)).font(.caption2)
                        Spacer()
                        Button {
                            vm.removePointMark(p)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                }
            }

            if vm.tracks.isEmpty && vm.routes.isEmpty && vm.pointMarks.isEmpty {
                Text("No GPX data loaded.\nUse \"Import GPX…\" in the toolbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Fences

    private var fencesContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Electronic Fences").font(.headline)

            if vm.fences.isEmpty {
                Text("No fences defined.\nClick \"Draw Fence\" in the toolbar, then click map vertices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(vm.fences) { f in
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 12, height: 12)
                    Text(f.name).lineLimit(1)
                    Text("\(f.vertices.count)v").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button { vm.removeFence(f) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption)
            }

            // Draw fence in progress
            if vm.isPlacingFence {
                HStack {
                    Image(systemName: "pencil.circle")
                    Text("Placing: \(vm.fenceDraftName)")
                    Text("\(vm.fenceDraftVertices.count) verts")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.caption)
                .padding(4)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: Beacons (location sharing)

    private var beaconsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location Sharing").font(.headline)
            Text("Beacons represent shared locations (self or peers).")
                .font(.caption2).foregroundStyle(.secondary)

            if vm.sharedBeacons.isEmpty {
                Text("No beacons.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(vm.sharedBeacons) { b in
                HStack {
                    Circle().fill(Color(hex: b.colorHex))
                        .frame(width: 10, height: 10)
                    Text(b.label).lineLimit(1)
                    Text(String(format: "%.4f,%.4f", b.lat, b.lng))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(b.lastSeen.formatted(date: .omitted, time: .standard))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .font(.caption)
            }

            // Quick add
            HStack {
                Text("Self @ center")
                Spacer()
                Button("Add") {
                    vm.addBeacon(
                        lat: vm.mapCenter.latitude,
                        lng: vm.mapCenter.longitude,
                        label: "Self"
                    )
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.subheadline).bold()
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .alphanumerics.inverted)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
