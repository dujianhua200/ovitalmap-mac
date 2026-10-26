import SwiftUI
import CoreLocation

/// A SwiftUI view that renders a custom tile map using AMAP public tiles
/// (or any Web Mercator slippy-map source). Does not depend on MapKit;
/// draws tiles directly with `Image` views positioned in screen space.
struct AMapTileView: View {
    let center: CLLocationCoordinate2D
    let zoomLevel: Double
    let tileSource: TileSource
    let onTap: (CLLocationCoordinate2D) -> Void

    /// Visible viewport width in points
    private let viewWidth: CGFloat = 1200
    private let viewHeight: CGFloat = 800

    var body: some View {
        VStack(spacing: 0) {
            TileCanvas(
                center: center,
                zoom: Int(zoomLevel),
                source: tileSource,
                tileSize: 256,
                onTap: onTap
            )
            .frame(width: viewWidth, height: viewHeight)
        }
    }
}

/// The actual tile-drawing canvas
struct TileCanvas: View {
    let center: CLLocationCoordinate2D
    let zoom: Int
    let source: TileSource
    let tileSize: Int
    let onTap: (CLLocationCoordinate2D) -> Void

    @State private var tileImages: [String: Data] = [:]
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color.black.opacity(0.05)

                // Compute which tiles are visible
                let tiles = visibleTiles(geo: geo)
                ForEach(tiles, id: \.self) { tile in
                    let key = "\(tile.z)_\(tile.x)_\(tile.y)"
                    if let data = tileImages[key],
                       let img = UIImage(data: data) {
                        let pixelSize = tileSize * pow(2, Double(tile.z - zoom))
                        let offset = tilePixelOffset(tile, geo: geo)
                        Image(uiImage: img)
                            .resizable()
                            .frame(width: pixelSize, height: pixelSize)
                            .offset(x: offset.x, y: offset.y)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: tileSize * pow(2, Double(tile.z - zoom)),
                                   height: tileSize * pow(2, Double(tile.z - zoom)))
                            .offset(x: tilePixelOffset(tile, geo: geo).x,
                                    y: tilePixelOffset(tile, geo: geo).y)
                    }
                }
            }
            .onAppear { loadTiles() }
            .onChange(of: center.latitude) { _ in loadTiles() }
            .onChange(of: center.longitude) { _ in loadTiles() }
            .onChange(of: zoom) { _ in loadTiles() }
            .onTapGesture { location in
                let coord = pixelToCoordinate(location, geo: geo)
                onTap(coord)
            }
        }
    }

    // MARK: - Tile computation

    private struct TileCoord: Hashable {
        let z: Int, x: Int, y: Int
    }

    private func visibleTiles(geo: GeometryProxy) -> [TileCoord] {
        let viewW = geo.size.width
        let viewH = geo.size.height
        // Number of tiles that fit in the viewport at this zoom level
        let tilesAcross = Int(ceil(viewW / Double(tileSize)))
        let tilesDown = Int(ceil(viewH / Double(tileSize)))

        // Center tile coordinates
        let centerTile = TileMath.wgs84ToTileCoords(lat: center.latitude,
                                                     lng: center.longitude, z: zoom)
        let centerX = Int(centerTile.x)
        let centerY = Int(centerTile.y)

        var result = [TileCoord]()
        for dy in -1...max(0, tilesDown) {
            for dx in -1...max(0, tilesAcross) {
                let tx = centerX + dx
                let ty = centerY + dy
                let zMax = 1 << zoom
                if tx >= 0 && tx < zMax && ty >= 0 && ty < zMax {
                    result.append(TileCoord(z: zoom, x: tx, y: ty))
                }
            }
        }
        return result
    }

    private func tilePixelOffset(_ tile: TileCoord, geo: GeometryProxy) -> CGPoint {
        // Where does this tile's top-left corner fall in view coordinates?
        let viewW = geo.size.width
        let viewH = geo.size.height
        let n = Double(1 << zoom)
        let totalWorldWidth = Double(tileSize) * n
        let tileScreenX = Double(tile.x) / n * totalWorldWidth
        let tileScreenY = Double(tile.y) / n * totalWorldWidth

        // Center of view in world pixels
        let centerWorld = TileMath.wgs84ToMercator(lat: center.latitude, lng: center.longitude)
        let worldCenterX = (centerWorld.x + 20_037_508.34) / (2 * 20_037_508.34) * totalWorldWidth
        let worldCenterY = (centerWorld.y + 20_037_508.34) / (2 * 20_037_508.34) * totalWorldWidth

        let screenCenterX = viewW / 2
        let screenCenterY = viewH / 2

        let dx = (tileScreenX - worldCenterX) + screenCenterX
        let dy = (tileScreenY - worldCenterY) + screenCenterY
        // Scale from world pixels to view pixels
        let scale = viewW / (totalWorldWidth / Double(tileSize) * Double(tilesVisibleAcross()))
        _ = scale
        // Simpler: tiles at `zoom` level render at `tileSize * 2^(zoom - displayZoom)` px
        // Since we're not implementing a zoom-scale difference, each tile = tileSize pixels
        return CGPoint(x: dx, y: dy)
    }

    private func tilesVisibleAcross() -> Int {
        Int(ceil(CGFloat(800) / Double(tileSize)))  // placeholder; actual width passed via geo
    }

    private func pixelToCoordinate(_ point: CGPoint, geo: GeometryProxy) -> CLLocationCoordinate2D {
        let viewW = geo.size.width
        let viewH = geo.size.height
        let n = Double(1 << zoom)
        let totalWorldWidth = Double(tileSize) * n
        let worldCenterX = (TileMath.wgs84ToMercator(lat: center.latitude, lng: center.longitude).x
                            + 20_037_508.34) / (2 * 20_037_508.34) * totalWorldWidth
        let worldCenterY = (TileMath.wgs84ToMercator(lat: center.latitude, lng: center.longitude).y
                            + 20_037_508.34) / (2 * 20_037_508.34) * totalWorldWidth

        let relX = Double(point.x - viewW / 2) + worldCenterX
        let relY = Double(point.y - viewH / 2) + worldCenterY
        let fractionX = relX / totalWorldWidth
        let fractionY = relY / totalWorldWidth

        let lng = fractionX * 360.0 - 180.0
        let lat = 180.0 / .pi * atan(0.5 * (exp(.pi * (1 - fractionY * 2))
                                            + exp(-.pi * (1 - fractionY * 2))))
        return .init(latitude: lat, longitude: lng)
    }

    // MARK: - Tile loading

    private func loadTiles() {
        guard !isLoading else { return }
        isLoading = true
        let tiles = visibleTiles(geo: GeometryProxy(size: CGSize(width: 800, height: 600)))
        for tile in tiles where tileImages["\(tile.z)_\(tile.x)_\(tile.y)"] == nil {
            let url = TileMath.fetchTile(tile.z, tile.x, tile.y, source: source)
            Task { @MainActor in
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    tileImages["\(tile.z)_\(tile.x)_\(tile.y)"] = data
                } catch {
                    // silent: tile will remain as gray placeholder
                }
                isLoading = false
            }
        }
    }
}
