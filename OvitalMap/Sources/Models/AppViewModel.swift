import Foundation
import CoreLocation
import SwiftUI
import Combine

// MARK: - Map Overlays (what to render on the map)

enum MapOverlayLayer: Hashable, Identifiable {
    case track(GPXTrajectoryData)
    case route(GPXRoute)
    case waypoints([GPXWaypoint])
    case fence(ElectronicFence)
    case pointMark([GeoPoint])

    var id: String {
        switch self {
        case .track:    return "track"
        case .route:    return "route"
        case .waypoints: return "waypoints"
        case .fence:    return "fence"
        case .pointMark: return "pointMark"
        }
    }
}

/// GPX trajectory data container for the UI
struct GPXTrajectoryData: Identifiable, Hashable {
    var id = UUID()
    var name: String?
    var segments: [[GPXTrackPoint]]
}

// MARK: - Coordinate Readout

struct CoordinateReadout: Identifiable, Hashable {
    var id = UUID()
    var lat: Double
    var lng: Double
    var text: String   // pre-formatted, e.g. "39.9042° N, 116.4074° E"
}

// MARK: - Location Sharing Model

/// A "shared" location beacon (peer or self)
struct SharedBeacon: Identifiable, Hashable {
    var id = UUID()
    var lat: Double
    var lng: Double
    var label: String
    var lastSeen: Date
    var colorHex: String = "#44AAFF"
}

// MARK: - App State

@MainActor
final class AppViewModel: ObservableObject {

    // ── Map state ──────────────────────────────────────────
    @Published var mapCenter: CLLocationCoordinate2D = .init(latitude: 39.9042, longitude: 116.4074) // Beijing
    @Published var zoomLevel: Double = 13
    @Published var activeTileSource: TileSource = .amapZhCN

    // ── Readout ────────────────────────────────────────────
    @Published var lastClickCoordinate: CLLocationCoordinate2D?
    @Published var coordinateReadout: String = "Click the map to read coordinates"

    // ── Layers ─────────────────────────────────────────────
    @Published var tracks: [GPXTrajectoryData] = []
    @Published var routes: [GPXRoute] = []
    @Published var fences: [ElectronicFence] = []
    @Published var pointMarks: [GeoPoint] = []
    @Published var sharedBeacons: [SharedBeacon] = []
    @Published var activeLayer: MapOverlayLayer?

    // ── Editing mode ───────────────────────────────────────
    @Published var isPlacingFence: Bool = false
    @Published var fenceDraftVertices: [GeoPoint] = []
    @Published var fenceDraftName: String = ""

    // ── Alert / message ────────────────────────────────────
    @Published var alertMessage: String?
    @Published var alertSeverity: AlertSeverity = .info

    // ── GPX import ─────────────────────────────────────────
    @Published var gpxImportCount: Int = 0

    // ── Derived: bounding box of all visible content ──────
    var allContentBoundingBox: GeoBoundingBox? {
        var points: [GeoPoint] = []
        for t in tracks {
            for seg in t.segments { for p in seg {
                points.append(GeoPoint(latitude: p.latitude, longitude: p.longitude))
            }}
        }
        for r in routes { for w in r.points {
            points.append(GeoPoint(latitude: w.latitude, longitude: w.longitude, label: w.name))
        }}
        for f in fences { points.append(contentsOf: f.vertices) }
        for p in pointMarks { points.append(p) }
        guard !points.isEmpty else { return nil }
        return GeoBoundingBox(
            minLat: points.map(\.latitude).min() ?? 0,
            maxLat: points.map(\.latitude).max() ?? 0,
            minLng: points.map(\.longitude).min() ?? 0,
            maxLng: points.map(\.longitude).max() ?? 0
        )
    }

    // MARK: - Actions

    /// Read the clicked map coordinate (convert to GCJ-02 if needed, then format)
    func mapClicked(at coord: CLLocationCoordinate2D) {
        lastClickCoordinate = coord
        let gcj = GCJ02.wgs84ToGCJ02(lat: coord.latitude, lng: coord.longitude)
        let nS = coord.latitude >= 0 ? "N" : "S"
        let eW = coord.longitude >= 0 ? "E" : "W"
        // 注意：%@ 才接受 Swift String；用 %s 会把 String 当作 C 字符串指针读取并导致崩溃。
        let wgsLat = String(format: "%.6f", abs(coord.latitude))
        let wgsLng = String(format: "%.6f", abs(coord.longitude))
        let gcjLat = String(format: "%.6f", abs(gcj.lat))
        let gcjLng = String(format: "%.6f", abs(gcj.lng))
        coordinateReadout = "WGS-84: \(wgsLat)°\(nS) \(wgsLng)°\(eW)\nGCJ-02: \(gcjLat)°\(nS) \(gcjLng)°\(eW)"
        // If in fence-placement mode, add vertex
        if isPlacingFence {
            fenceDraftVertices.append(GeoPoint(latitude: coord.latitude, longitude: coord.longitude))
        }
    }

    /// Begin placing a new electronic fence
    func startFencePlacement(name: String) {
        fenceDraftName = name
        fenceDraftVertices.removeAll()
        isPlacingFence = true
        activeLayer = .fence(ElectronicFence(name: name, vertices: []))
    }

    /// Finish fence placement — requires ≥3 vertices
    func finishFencePlacement() {
        guard fenceDraftVertices.count >= 3 else {
            // 顶点不足时只提示，保持绘制模式，允许用户继续点选补足。
            alertMessage = "Need at least 3 vertices to form a fence polygon"
            alertSeverity = .warning
            return
        }
        let fence = ElectronicFence(name: fenceDraftName, vertices: fenceDraftVertices)
        fences.append(fence)
        isPlacingFence = false
        fenceDraftVertices.removeAll()
        activeLayer = nil
        alertMessage = "Fence \"\(fence.name)\" created (\(fence.vertices.count) vertices)"
        alertSeverity = .info
    }

    /// Cancel fence placement
    func cancelFencePlacement() {
        isPlacingFence = false
        fenceDraftVertices.removeAll()
    }

    /// Remove a fence
    func removeFence(_ fence: ElectronicFence) {
        fences.removeAll { $0.id == fence.id }
    }

    /// Clear all fences
    func clearAllFences() {
        fences.removeAll()
    }

    /// Add a named point mark
    func addPointMark(at coord: CLLocationCoordinate2D, label: String) {
        pointMarks.append(GeoPoint(latitude: coord.latitude, longitude: coord.longitude, label: label))
    }

    /// Remove a point mark
    func removePointMark(_ point: GeoPoint) {
        pointMarks.removeAll { $0.id == point.id }
    }

    /// Add a shared beacon
    func addBeacon(lat: Double, lng: Double, label: String, colorHex: String = "#44AAFF") {
        sharedBeacons.append(SharedBeacon(lat: lat, lng: lng, label: label,
                                          lastSeen: Date(), colorHex: colorHex))
    }

    /// Check whether a point is inside any active fence
    func isInsideAnyFence(_ coord: CLLocationCoordinate2D) -> ElectronicFence? {
        let point = GeoPoint(latitude: coord.latitude, longitude: coord.longitude)
        return fences.first { $0.contains(point: point) }
    }

    /// Import a GPX file
    func importGPX(_ data: Data) {
        do {
            let gpx = try GPXParser.parse(data)
            var newTracks: [GPXTrajectoryData] = []
            for trk in gpx.tracks {
                newTracks.append(GPXTrajectoryData(name: trk.name, segments: trk.segments))
            }
            tracks.append(contentsOf: newTracks)
            routes.append(contentsOf: gpx.routes)
            // 航点也进入图层，否则提示里统计了数量、界面上却看不到。
            for w in gpx.waypoints {
                pointMarks.append(GeoPoint(latitude: w.latitude, longitude: w.longitude, label: w.name))
            }
            gpxImportCount += 1
            alertMessage = "Imported \(gpx.tracks.count) track(s), \(gpx.routes.count) route(s), \(gpx.waypoints.count) waypoint(s)"
            alertSeverity = .success
            // Auto-zoom to content
            fitAllContent()
        } catch {
            alertMessage = "GPX import failed: \(error.localizedDescription)"
            alertSeverity = .error
        }
    }

    /// Zoom the map to fit all loaded content
    func fitAllContent() {
        guard let box = allContentBoundingBox else { return }
        let midLat = (box.minLat + box.maxLat) / 2
        let midLng = (box.minLng + box.maxLng) / 2
        let latSpan = box.maxLat - box.minLat
        let lngSpan = box.maxLng - box.minLng
        let span = max(latSpan, lngSpan)
        // Heuristic zoom: fit ~80% of screen height
        let zoom: Double = span > 50 ? 4 : span > 20 ? 6 : span > 5 ? 8 : span > 1 ? 11 : 14
        mapCenter = .init(latitude: midLat, longitude: midLng)
        zoomLevel = min(18, max(3, zoom))
    }

    /// Remove all GPX data
    func clearAllGPX() {
        tracks.removeAll()
        routes.removeAll()
    }
}

// MARK: - Alert severity

enum AlertSeverity: Hashable {
    case info, success, warning, error
}
