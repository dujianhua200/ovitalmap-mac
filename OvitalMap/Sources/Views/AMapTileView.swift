import SwiftUI
import CoreLocation
import Foundation

/// Observable container for the tile image dictionary, held by the view via
/// `@StateObject` so background tasks can mutate it safely.
final class TileImageStore: ObservableObject {
    @Published var images: [String: NSImage] = [:]
}

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

    @StateObject private var store = TileImageStore()

    var body: some View {
        GeometryReader { geo in
            let tiles = visibleTiles(viewSize: geo.size)
            ZStack {
                Color(white: 0.5).opacity(0.3)
                ForEach(tiles, id: \.key) { tile in
                    let key = tile.key
                    let offset = tileScreenOffset(tile: tile, viewSize: geo.size)
                    Group {
                        if let img = store.images[key] {
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
            .onChange(of: source) { _ in loadTiles(viewSize: geo.size) }
            .onChange(of: geo.size) { _ in loadTiles(viewSize: geo.size) }
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
        var id: String { key }
        var key: String { "\(z)_\(x)_\(y)" }
    }

    /// 中心点在该瓦片源坐标系下的投影（高德为 GCJ-02）。
    private func projectedCenter() -> (lat: Double, lng: Double) {
        source.project(lat: center.latitude, lng: center.longitude)
    }

    /// 视图中心对应的世界像素坐标。原点在左上角，y 向南递增。
    private func centerWorldPixel() -> (x: Double, y: Double) {
        let worldWidth = Double(tileSize) * Double(1 << zoom)
        let p = projectedCenter()
        let merc = TileMath.wgs84ToMercator(lat: p.lat, lng: p.lng)
        let x = (merc.x + 20_037_508.34) / (2 * 20_037_508.34) * worldWidth
        // 注意：Mercator 的 y 向北为正，而像素 y 向南为正，两者方向相反。
        let y = (20_037_508.34 - merc.y) / (2 * 20_037_508.34) * worldWidth
        return (x, y)
    }

    /// 覆盖当前视口所需的瓦片，按视口范围计算而非固定 3×3。
    private func visibleTiles(viewSize: CGSize) -> [Tile] {
        let zMax = 1 << zoom
        let centerPx = centerWorldPixel()
        let left = centerPx.x - Double(viewSize.width) / 2
        let top = centerPx.y - Double(viewSize.height) / 2
        let right = centerPx.x + Double(viewSize.width) / 2
        let bottom = centerPx.y + Double(viewSize.height) / 2

        let minX = max(0, Int(floor(left / Double(tileSize))))
        let maxX = min(zMax - 1, Int(floor(right / Double(tileSize))))
        let minY = max(0, Int(floor(top / Double(tileSize))))
        let maxY = min(zMax - 1, Int(floor(bottom / Double(tileSize))))
        guard minX <= maxX, minY <= maxY else { return [] }

        var result = [Tile]()
        for ty in minY...maxY {
            for tx in minX...maxX {
                result.append(Tile(z: zoom, x: tx, y: ty))
            }
        }
        return result
    }

    /// 瓦片左上角在视图坐标系中的位置。
    private func tileScreenOffset(tile: Tile, viewSize: CGSize) -> CGPoint {
        let centerPx = centerWorldPixel()
        let worldTLx = Double(tile.x * tileSize)
        let worldTLy = Double(tile.y * tileSize)
        return CGPoint(
            x: worldTLx - centerPx.x + Double(viewSize.width) / 2,
            y: worldTLy - centerPx.y + Double(viewSize.height) / 2
        )
    }

    /// 把点击位置换回 WGS-84 坐标（高德瓦片先按 GCJ-02 反投影）。
    private func pixelToCoordinate(_ point: CGPoint, viewSize: CGSize) -> CLLocationCoordinate2D {
        let worldWidth = Double(tileSize) * Double(1 << zoom)
        let centerPx = centerWorldPixel()
        let worldX = Double(point.x) - Double(viewSize.width) / 2 + centerPx.x
        let worldY = Double(point.y) - Double(viewSize.height) / 2 + centerPx.y

        let fracX = worldX / worldWidth
        let fracY = min(1, max(0, worldY / worldWidth))

        let lng = fracX * 360.0 - 180.0
        // Web Mercator 反算：lat = atan(sinh(π(1 − 2·fracY)))，这里必须是 sinh 而不是 cosh。
        let lat = 180.0 / Double.pi * atan(sinh(Double.pi * (1.0 - 2.0 * fracY)))
        let wgs = source.unproject(lat: lat, lng: lng)
        return .init(latitude: wgs.lat, longitude: wgs.lng)
    }

    // MARK: - Tile loading

    /// 单元测试宿主中不发起网络请求，避免 CI 因网络抖动而不稳定。
    private static let tileFetchDisabled =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    private func loadTiles(viewSize: CGSize) {
        guard !Self.tileFetchDisabled,
              viewSize.width > 0, viewSize.height > 0 else { return }
        let tiles = visibleTiles(viewSize: viewSize)
        for tile in tiles where store.images[tile.key] == nil {
            let url = TileMath.fetchTile(tile.z, tile.x, tile.y, source: source)
            let key = tile.key
            // Check the shared actor cache first, then fetch from the network.
            // Network failures are silent so a CI host without internet does
            // not crash. `store` is a class reference, so `weak` is valid.
            Task.detached { [weak store] in
                guard let store = store else { return }
                // 1. Try in-memory cache
                if let cached = await TileImageCache.shared.get(z: tile.z, x: tile.x, y: tile.y),
                   let image = NSImage(data: cached) {
                    await MainActor.run { store.images[key] = image }
                    return
                }
                // 2. Fetch from network
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard let image = NSImage(data: data) else { return }
                    await TileImageCache.shared.put(z: tile.z, x: tile.x, y: tile.y, data: data)
                    await MainActor.run { store.images[key] = image }
                } catch {
                    // Unsupported URL / no network in CI — skip silently.
                }
            }
        }
    }
}
