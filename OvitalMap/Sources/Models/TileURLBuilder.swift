import Foundation

/// Builds tile URLs for a slippy map (web Mercator) tile source.
/// For AMAP public tiles the URL pattern is:
///   https://webrd0{1-4}.is.autonavi.com/appmaptile?lang=zh_cn&size=256&scale=1&style=7&x={x}&y={y}&z={z}
/// where lang can be `zh_cn`, `en`, or `ja`.
///
/// The tile is always returned as WGS-84 pixel space; the caller is responsible
/// for whether coordinates passed to MapKit must be converted (GCJ-02 vs WGS-84).
enum TileSource: Hashable, Identifiable, CaseIterable, Codable {
    case amapZhCN
    case amapEN
    case amapJa
    case osm

    var id: String { "\(self)" }

    var displayName: String {
        switch self {
        case .amapZhCN: return "高德中文"
        case .amapEN:   return "Amap EN"
        case .amapJa:   return "Amap 日"
        case .osm:      return "OpenStreetMap"
        }
    }

    /// Returns the tile URL for (z, x, y). Uses a deterministic shard 1–4
    /// for AMAP so the cache key is stable but the hostname is rotated.
    func tileURL(z: Int, x: Int, y: Int) -> URL {
        switch self {
        case .amapZhCN:
            return amapURL(z: z, x: x, y: y, lang: "zh_cn")
        case .amapEN:
            return amapURL(z: z, x: x, y: y, lang: "en")
        case .amapJa:
            return amapURL(z: z, x: x, y: y, lang: "ja")
        case .osm:
            let host: String
            if (x + y) % 2 == 0 {
                host = "tile.openstreetmap.org"
            } else {
                host = "tile-a.openstreetmap.org"
            }
            return URL(string: "https://\(host)/\(z)/\(x)/\(y).png")!
        }
    }

    private func amapURL(z: Int, x: Int, y: Int, lang: String) -> URL {
        let shard = 1 + ((x &* y &* 31) % 4)
        let host = "webrd\(shard).is.autonavi.com"
        // 必须带 scheme，否则 URL 会被解析成相对路径，URLSession 报 -1002 unsupported URL。
        return URL(string: "https://\(host)/appmaptile?lang=\(lang)&size=256&scale=1&style=7&x=\(x)&y=\(y)&z=\(z)")!
    }

    /// 瓦片使用的坐标系是否为 GCJ-02（高德系）。
    var usesGCJ02: Bool {
        switch self {
        case .amapZhCN, .amapEN, .amapJa: return true
        case .osm: return false
        }
    }

    /// 把 WGS-84 坐标投影到该瓦片源的坐标系。
    func project(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        usesGCJ02 ? GCJ02.wgs84ToGCJ02(lat: lat, lng: lng) : (lat, lng)
    }

    /// 把该瓦片源坐标系下的坐标还原为 WGS-84。
    func unproject(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        usesGCJ02 ? GCJ02.gcj02ToWGS84(lat: lat, lng: lng) : (lat, lng)
    }
}

/// Tile coordinate math helpers for Web Mercator (EPSG:3857)
enum TileMath {

    /// Tile size in pixels (standard)
    static let tileSize: Int = 256

    /// Convert (latitude, longitude) in WGS-84 to Web Mercator x/y in meters
    /// within the Mercator square of [-20037508.34, 20037508.34].
    static func wgs84ToMercator(lat: Double, lng: Double) -> (x: Double, y: Double) {
        let r = 6378137.0
        let mx = r * lng * .pi / 180.0
        let latRad = lat * .pi / 180.0
        let my = r * log(tan(latRad / 2 + .pi / 4))
        return (mx, my)
    }

    /// Convert Web Mercator x/y back to WGS-84 lat/lng
    static func mercatorToWGS84(x: Double, y: Double) -> (lat: Double, lng: Double) {
        let r = 6378137.0
        let lng = x / r * 180.0 / .pi
        let lat = (2 * atan(exp(y / r)) - .pi / 2) * 180.0 / .pi
        return (lat, lng)
    }

    /// Convert WGS-84 lat/lng to tile x/y at zoom z (integer, zero-based)
    static func wgs84ToTileCoords(lat: Double, lng: Double, z: Int) -> (x: Int, y: Int) {
        let n = Double(1 << z)
        let rawX = (lng + 180.0) / 360.0 * n
        var tx = Int(floor(rawX))
        tx = min(max(tx, 0), Int(n) - 1)
        let latRad = lat * Double.pi / 180.0
        let rawY = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / Double.pi) / 2.0 * n
        var ty = Int(floor(rawY))
        ty = min(max(ty, 0), Int(n) - 1)
        return (tx, ty)
    }

    /// Convert tile x/y at zoom z to the WGS-84 coordinate of the tile's northwest corner
    static func tileCoordsToWGS84(x: Int, y: Int, z: Int) -> (lat: Double, lng: Double) {
        let n = Double(1 << z)
        let lng = Double(x) / n * 360.0 - 180.0
        let t = Double.pi - 2.0 * Double.pi * Double(y) / n
        let lat = 180.0 / Double.pi * atan(0.5 * (exp(t) - exp(-t)))
        return (lat, lng)
    }

    /// The URL for fetching a tile image
    static func fetchTile(_ z: Int, _ x: Int, _ y: Int, source: TileSource = .amapZhCN) -> URL {
        source.tileURL(z: z, x: x, y: y)
    }
}
