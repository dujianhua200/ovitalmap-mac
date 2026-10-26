import SwiftUI
import CoreLocation

/// Renders the map view and all GPX / fence overlays on top of the tile canvas.
struct MapCanvasView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ZStack {
            // Tile background
            AMapTileView(
                center: vm.mapCenter,
                zoomLevel: vm.zoomLevel,
                tileSource: vm.activeTileSource
            ) { coord in
                vm.mapClicked(at: coord)
            }

            // Overlays (drawn in a Canvas relative to view space)
            OverlayLayerView(vm: vm)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

/// Draws GPX tracks, routes, fences and point marks on top of the tiles.
/// Uses SwiftUI Canvas for vector overlay drawing.
struct OverlayLayerView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        GeometryReader { geo in
            // Capture the MainActor-isolated state in locals before the Canvas
            // closure so the (non-isolated) renderer can read plain values.
            let center = vm.mapCenter
            let zoom = Int(vm.zoomLevel)
            let fences = vm.fences
            let placingFence = vm.isPlacingFence
            let draftVerts = vm.fenceDraftVertices
            let tracks = vm.tracks
            let routes = vm.routes
            let marks = vm.pointMarks
            let beacons = vm.sharedBeacons
            let lastClick = vm.lastClickCoordinate

            Canvas { ctx, size in
                func project(lat: Double, lng: Double) -> CGPoint {
                    let z = zoom
                    let n = Double(1 << z)
                    let tileSize: Double = 256
                    let totalWorldWidth = tileSize * n
                    let merc = TileMath.wgs84ToMercator(lat: lat, lng: lng)
                    let mercCenter = TileMath.wgs84ToMercator(lat: center.latitude,
                                                               lng: center.longitude)
                    let relX = merc.x - mercCenter.x
                    let relY = merc.y - mercCenter.y
                    let pxPerMercM = size.width / (totalWorldWidth / tileSize * 8.0)
                    let x = size.width / 2 + relX * pxPerMercM
                    let y = size.height / 2 + relY * pxPerMercM
                    return CGPoint(x: x, y: y)
                }

                // ── Fences ────────────────────────────────
                for fence in fences {
                    guard fence.vertices.count >= 2 else { continue }
                    var path = Path()
                    path.move(to: project(lat: fence.vertices[0].latitude,
                                          lng: fence.vertices[0].longitude))
                    for v in fence.vertices.dropFirst() {
                        path.addLine(to: project(lat: v.latitude, lng: v.longitude))
                    }
                    path.closeSubpath()
                    ctx.fill(path, with: .color(.red.opacity(0.20)))
                    ctx.stroke(path, with: .color(.red.opacity(0.8)), lineWidth: 2)
                }

                // Fence draft
                if placingFence, draftVerts.count >= 2 {
                    var path = Path()
                    path.move(to: project(lat: draftVerts[0].latitude,
                                          lng: draftVerts[0].longitude))
                    for v in draftVerts.dropFirst() {
                        path.addLine(to: project(lat: v.latitude, lng: v.longitude))
                    }
                    ctx.stroke(path, with: .color(.orange),
                               style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                }

                // ── GPX Tracks ─────────────────────────────
                for track in tracks {
                    for seg in track.segments {
                        guard seg.count >= 2 else { continue }
                        var path = Path()
                        path.move(to: project(lat: seg[0].latitude, lng: seg[0].longitude))
                        for p in seg.dropFirst() {
                            path.addLine(to: project(lat: p.latitude, lng: p.longitude))
                        }
                        ctx.stroke(path, with: .color(.blue.opacity(0.85)), lineWidth: 3)
                    }
                }

                // ── Routes ─────────────────────────────────
                for route in routes {
                    guard route.points.count >= 2 else { continue }
                    var path = Path()
                    path.move(to: project(lat: route.points[0].latitude,
                                          lng: route.points[0].longitude))
                    for p in route.points.dropFirst() {
                        path.addLine(to: project(lat: p.latitude, lng: p.longitude))
                    }
                    ctx.stroke(path, with: .color(.green.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                }

                // ── Point marks ────────────────────────────
                for p in marks {
                    let pt = project(lat: p.latitude, lng: p.longitude)
                    let r: CGFloat = 5
                    let circle = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r,
                                                         width: r * 2, height: r * 2))
                    ctx.fill(circle, with: .color(.orange))
                    ctx.stroke(circle, with: .color(.white), lineWidth: 1.5)
                }

                // ── Beacons ────────────────────────────────
                for b in beacons {
                    let pt = project(lat: b.lat, lng: b.lng)
                    let r: CGFloat = 7
                    let circle = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r,
                                                         width: r * 2, height: r * 2))
                    ctx.fill(circle, with: .color(Color(hex: b.colorHex).opacity(0.55)))
                    ctx.stroke(circle, with: .color(Color(hex: b.colorHex)), lineWidth: 2)
                }

                // ── Last click marker ──────────────────────
                if let c = lastClick {
                    let pt = project(lat: c.latitude, lng: c.longitude)
                    let cross: CGFloat = 8
                    var crossPath = Path()
                    crossPath.move(to: CGPoint(x: pt.x - cross, y: pt.y))
                    crossPath.addLine(to: CGPoint(x: pt.x + cross, y: pt.y))
                    crossPath.move(to: CGPoint(x: pt.x, y: pt.y - cross))
                    crossPath.addLine(to: CGPoint(x: pt.x, y: pt.y + cross))
                    ctx.stroke(crossPath, with: .color(.white), lineWidth: 2)
                }
            }
        }
    }
}
