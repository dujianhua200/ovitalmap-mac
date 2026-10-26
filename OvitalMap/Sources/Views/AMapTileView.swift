import SwiftUI
import CoreLocation

/// A SwiftUI view that renders a custom tile map using AMAP public tiles
/// (or any Web Mercator slippy-map source). Does not depend on MapKit;
/// draws tiles directly with `Image` views positioned in screen space.
///
/// macOS note: uses `NSImage` (not `UIImage`) and decodes off the main thread
/// via a background `Task`.
struct AMapTileView: View {
    let center: CLLocationCoordinate2D
    let zoomLevel: Double
    let tileSource: TileSource
    let onTap: (CLLocationCoordinate2D) -> Void

    var body: some View {
        TileCanvas(
            center: center,
            zoom: Int(zoomLevel),
            source: tileSource,
            tileSize: 256,
            onTap: onTap
        )
    }
}

/// The actual tile-drawing canvas. Draws a grid of tiles around the center
/// coordinate; each tile is fetched from the tile source and rendered as an
/// `Image(nsImage:)`.
struct TileCanvas: View {
    let center: CLLocationCoordinate2D
    let zoom: Int
    let source: TileSource
    let tileSize: Int
    let onTap: (CLLocationCoordinate2D) -> Void

    @State private var tileImages: [String: NSImage] = [:]

    /// Fixed viewport size (the parent frame controls the actual layout size).
    private let viewWidth: CGFloat = 1000
    private let viewHeight: CGFloat = 700

    var body: some View {
        GeometryReader { geo in
            let tiles = visibleTiles(viewSize: geo.size)
            ZStack {
                Color(white: 0.5).opacity(0.3)
                ForEach(tiles, id: \.key) { tile in
                    let key = tile.key
                    let offset = tileScreenOffset(tile: tile, viewSize: geo.size)
                    Group {
                        if let img = tileImages[key] {
                            Image(nsImage: img)
                                .resizable()
                        } else {
                            Rectangle().fill(Color.gray.opacity(0.2))
                        }
                    }
                    .frame(width: CGFloat(tileSize), height: CGFloat(tileSize))
                    .offset(x: offset.x, y: offset.y)
                }
            }
            .clipped()
            .onAppear { loadTiles(viewSize: geo.size) }
            .onChange(of: center.latitude) { _ in loadTiles(viewSize: geo.size) }
            .onChange(of: center.longitude) { _ in loadTiles(viewSize: geo.size) }
            .onChange(of: zoom) { _ in loadTiles(viewSize: geo.size) }
            .onTapGesture { location in
                let coord = pixelToCoordinate(location, viewSize: geo.size)
                onTap(coord)
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }

    // MARK: - Tile grid math

    private struct Tile: Identifiable, Hashable {
        let z: Int, x: Int, y: Int
        var id: Int { y * 100_000 + x }
        var key: String { "\(z)_\(x)_\(y)" }
    }

    private func visibleTiles(viewSize: CGSize) -> [Tile] {
        let centerTile = TileMath.wgs84ToTileCoords(lat: center.latitude,
                                                     lng: center.longitude, z: zoom)
        // 3x3 grid of tiles around the center tile
        var result = [Tile]()
        for dy in -1...1 {
            for dx in -1...1 {
                let tx = centerTile.x + dx
                let ty = centerTile.y + dy
                let zMax = 1 << zoom
                if tx >= 0 && tx < zMax && ty >= 0 && ty < zMax {
                    result.append(Tile(z: zoom, x: tx, y: ty))
                }
            }
        }
        return result
    }

    /// Where to place a tile's top-left corner in view coordinates.
    private func tileScreenOffset(tile: Tile, viewSize: CGSize) -> CGPoint {
        let n = Double(1 << zoom)
        // World-pixel position of the tile's top-left corner
        let worldTLx = Double(tile.x) * Double(tileSize)
        let worldTLy = Double(tile.y) * Double(tileSize)

        // World-pixel position of the view's center (i.e. center coordinate)
        let mercCenter = TileMath.wgs84ToMercator(lat: center.latitude, lng: center.longitude)
        let totalWorldWidth = Double(tileSize) * n
        let mercCenterPxX = (mercCenter.x + 20_037_508.34) / (2 * 20_037_508.34) * totalWorldWidth
        let mercCenterPxY = (mercCenter.y + 20_037_508.34) / (2 * 20_037_508.34) * totalWorldWidth

        let viewCenterX = viewSize.width / 2
        let viewCenterY = viewSize.height / 2

        return CGPoint(
            x: (worldTLx - mercCenterPxX) + viewCenterX,
            y: (worldTLy - mercCenterPxY) + viewCenterY
        )
    }

    /// Convert a view-space point (from `onTapGesture`) back to a WGS-84 coordinate.
    private func pixelToCoordinate(_ point: CGPoint, viewSize: CGSize) -> CLLocationCoordinate2D {
        let n = Double(1 << zoom)
        let totalWorldWidth = Double(tileSize) * n
        let mercCenter = TileMath.wgs84ToMercator(lat: center.latitude, lng: center.longitude)
        let mercCenterPxX = (mercCenter.x + 20_037_508.34) / (2 * 20_037_508.34) * totalWorldWidth
        let mercCenterPxY = (mercCenter.y + 20_037_508.34) / (2 * 20_037_508.34) * totalWorldWidth

        let relPxX = Double(point.x - viewSize.width / 2) + mercCenterPxX
        let relPxY = Double(point.y - viewSize.height / 2) + mercCenterPxY

        let fracX = relPxX / totalWorldWidth
        let fracY = relPxY / totalWorldWidth

        let lng = fracX * 360.0 - 180.0
        let lat = 180.0 / Double.pi * atan(0.5 * (exp(Double.pi * (1.0 - fracY * 2.0))
                                                   + exp(-Double.pi * (1.0 - fracY * 2.0))))
        return .init(latitude: lat, longitude: lng)
    }

    // MARK: - Tile loading

    private func loadTiles(viewSize: CGSize) {
        let tiles = visibleTiles(viewSize: viewSize)
        for tile in tiles where tileImages[tile.key] == nil {
            let url = TileMath.fetchTile(tile.z, tile.x, tile.y, source: source)
            let key = tile.key
            Task { @MainActor in
                guard let data = try? await URLSession.shared.data(from: url).0,
                      let image = NSImage(data: data) else { return }
                // Mutate @State from MainActor
                self.tileImages[key] = image
            }
        }
    }
}
