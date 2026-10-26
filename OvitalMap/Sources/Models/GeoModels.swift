import Foundation
import CoreLocation

// MARK: - Coordinate System Definitions

/// Geographic coordinate system enum
enum GeoCoordinateSystem: String, Codable, CaseIterable, Identifiable {
    case wgs84 = "WGS-84"
    case gcj02 = "GCJ-02"
    case bd09  = "BD-09"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

/// A coordinate point with optional metadata
struct GeoPoint: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var latitude: Double
    var longitude: Double
    var label: String?
    var colorHex: String?
    var timestamp: Date?

    init(latitude: Double, longitude: Double, label: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
    }
}

// MARK: - GPX Track

/// GPX track point (coordinates + time)
struct GPXTrackPoint: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var time: Date?
}

/// GPX waypoint
struct GPXWaypoint: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var latitude: Double
    var longitude: Double
    var name: String?
}

/// GPX route segment
struct GPXRoute: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String?
    var points: [GPXWaypoint]

    var coordinateArray: [GeoPoint] {
        points.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude, label: $0.name) }
    }
}

/// GPX track (collection of segments)
struct GPXTrack: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String?
    var segments: [[GPXTrackPoint]]

    var firstPoint: GPXTrackPoint? {
        segments.first?.first
    }

    var totalDistance: Double {
        var total: Double = 0
        for seg in segments {
            for i in 1..<seg.count {
                total += seg[i-1].haversineDistance(to: seg[i])
            }
        }
        return total
    }

    var totalDuration: TimeInterval {
        let times = segments.flatMap { $0.compactMap { $0.time } }.sorted()
        guard let first = times.first, let last = times.last else { return 0 }
        return last.timeIntervalSince(first)
    }
}

/// Root GPX container
struct GPXFile: Codable {
    let version: String
    let creator: String?
    let waypoints: [GPXWaypoint]
    let tracks: [GPXTrack]
    let routes: [GPXRoute]

    enum CodingKeys: String, CodingKey {
        case version, creator, waypoints
        case tracks = "trk"
        case routes = "rte"
    }

    init(version: String, creator: String? = nil,
         waypoints: [GPXWaypoint] = [],
         tracks: [GPXTrack] = [],
         routes: [GPXRoute] = []) {
        self.version = version
        self.creator = creator
        self.waypoints = waypoints
        self.tracks = tracks
        self.routes = routes
    }
}

// MARK: - Electronic Fence

/// A polygonal fence region defined by coordinate vertices
struct ElectronicFence: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var vertices: [GeoPoint]
    var colorHex: String = "#FF4444"

    /// Compute whether a point is inside the polygon (ray casting)
    func contains(point: GeoPoint) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        var j = vertices.count - 1
        for i in vertices.indices {
            let a = vertices[i]
            let b = vertices[j]
            if ((a.latitude > point.latitude) != (b.latitude > point.latitude)) &&
                (point.longitude < (b.longitude - a.longitude) *
                    (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Bounding box for the polygon
    var boundingBox: GeoBoundingBox {
        let lats = vertices.map(\.latitude)
        let lngs = vertices.map(\.longitude)
        return GeoBoundingBox(
            minLat: lats.min() ?? 0, maxLat: lats.max() ?? 0,
            minLng: lngs.min() ?? 0, maxLng: lngs.max() ?? 0
        )
    }
}

/// Bounding box in geographic coordinates
struct GeoBoundingBox: Codable, Hashable {
    var minLat: Double
    var maxLat: Double
    var minLng: Double
    var maxLng: Double

    func contains(point: GeoPoint) -> Bool {
        point.latitude >= minLat && point.latitude <= maxLat &&
        point.longitude >= minLng && point.longitude <= maxLng
    }
}

// MARK: - Distance & Geodesy

extension GPXTrackPoint {
    /// Haversine distance in meters between two GPX points
    func haversineDistance(to other: GPXTrackPoint) -> Double {
        let r = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180.0
        let dLng = (other.longitude - longitude) * .pi / 180.0
        let a = sin(dLat/2)*sin(dLat/2) +
                cos(latitude * .pi/180) * cos(other.latitude * .pi/180) *
                sin(dLng/2)*sin(dLng/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        return r * c
    }
}

// MARK: - GCJ-02 Conversion (WGS-84 <-> GCJ-02)

/// GCJ-02 (Mars Coordinate System) conversion used by Chinese map providers (AMap, Baidu)
enum GCJ02 {

    static let a = 6378245.0               // Krasovsky semi-major axis
    static let ee = 0.00669342162296594323 // Krasovsky eccentricity squared

    /// Check whether a WGS-84 point falls inside mainland China (approximate)
    static func isInChina(lat: Double, lng: Double) -> Bool {
        return lng >= 72.004 && lng <= 137.8347 && lat >= 0.8293 && lat <= 55.8271
    }

    /// Convert WGS-84 to GCJ-02
    static func wgs84ToGCJ02(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        if !isInChina(lat: lat, lng: lng) {
            return (lat, lng)
        }
        var dLat = transformLat(x: lng - 105.0, y: lat - 35.0)
        var dLng = transformLng(x: lng - 105.0, y: lat - 35.0)
        let radLat = lat / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * Double.pi)
        dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * Double.pi)
        return (lat + dLat, lng + dLng)
    }

    /// Convert GCJ-02 to WGS-84 (iterative refinement)
    static func gcj02ToWGS84(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        if !isInChina(lat: lat, lng: lng) {
            return (lat, lng)
        }
        // 一次反解（2x − forward）误差可达 1e-5°，这里迭代修正到亚米级。
        var wgsLat = lat
        var wgsLng = lng
        for _ in 0..<5 {
            let fwd = wgs84ToGCJ02(lat: wgsLat, lng: wgsLng)
            wgsLat += lat - fwd.lat
            wgsLng += lng - fwd.lng
        }
        return (wgsLat, wgsLng)
    }

    // Krasovsky transformation helpers
    // 系数取自公开的 GCJ-02 标准实现，改动前请先用已知坐标做回归验证。
    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0*x + 3.0*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        ret += (20.0 * sin(6.0*x*Double.pi) + 20.0 * sin(2.0*x*Double.pi)) * 2.0/3.0
        ret += (20.0 * sin(y*Double.pi) + 40.0 * sin(y/3.0*Double.pi)) * 2.0/3.0
        ret += (160.0 * sin(y/12.0*Double.pi) + 320.0 * sin(y*Double.pi/30.0)) * 2.0/3.0
        return ret
    }

    private static func transformLng(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        ret += (20.0 * sin(6.0*x*Double.pi) + 20.0 * sin(2.0*x*Double.pi)) * 2.0/3.0
        ret += (20.0 * sin(x*Double.pi) + 40.0 * sin(x/3.0*Double.pi)) * 2.0/3.0
        ret += (150.0 * sin(x/12.0*Double.pi) + 300.0 * sin(x/30.0*Double.pi)) * 2.0/3.0
        return ret
    }
}
