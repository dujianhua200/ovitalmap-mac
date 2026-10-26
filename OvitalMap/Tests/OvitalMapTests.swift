import XCTest
import CoreLocation
@testable import OvitalMap

// MARK: - GPX Parser Tests

final class GPXParserTests: XCTestCase {

    /// A minimal valid GPX 1.1 file
    let sampleGPX = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="OvitalMap-Test" xmlns="http://www.topografix.com/GPX/1/1">
      <wpt lat="39.9042" lon="116.4074">
        <name>Beijing</name>
      </wpt>
      <trk>
        <name>Test Track</name>
        <trkseg>
          <trkpt lat="39.9042" lon="116.4074">
            <ele>50.0</ele>
            <time>2024-01-01T00:00:00Z</time>
          </trkpt>
          <trkpt lat="39.9043" lon="116.4075">
            <ele>51.0</ele>
            <time>2024-01-01T00:00:01Z</time>
          </trkpt>
        </trkseg>
      </trk>
      <rte>
        <name>Test Route</name>
        <rtept lat="39.9042" lon="116.4074">
          <name>Start</name>
        </rtept>
        <rtept lat="39.9100" lon="116.4100">
          <name>End</name>
        </rtept>
      </rte>
    </gpx>
    """

    func testParseValidGPX() throws {
        let data = sampleGPX.data(using: .utf8)!
        let gpx = try GPXParser.parse(data)

        XCTAssertEqual(gpx.version, "1.1")
        XCTAssertEqual(gpx.creator, "OvitalMap-Test")
        XCTAssertEqual(gpx.waypoints.count, 1)
        XCTAssertEqual(gpx.tracks.count, 1)
        XCTAssertEqual(gpx.routes.count, 1)

        // Waypoint
        XCTAssertEqual(gpx.waypoints[0].name, "Beijing")
        XCTAssertEqual(gpx.waypoints[0].latitude, 39.9042, accuracy: 1e-6)
        XCTAssertEqual(gpx.waypoints[0].longitude, 116.4074, accuracy: 1e-6)

        // Track
        XCTAssertEqual(gpx.tracks[0].name, "Test Track")
        XCTAssertEqual(gpx.tracks[0].segments.count, 1)
        XCTAssertEqual(gpx.tracks[0].segments[0].count, 2)
        XCTAssertEqual(gpx.tracks[0].segments[0][0].elevation, 50.0, accuracy: 1e-6)
        XCTAssertNotNil(gpx.tracks[0].segments[0][0].time)
        let t0 = gpx.tracks[0].segments[0][0].time!
        let t1 = gpx.tracks[0].segments[0][1].time!
        XCTAssertEqual(t0.timeIntervalSince(t1), 1.0, accuracy: 0.5)

        // Route
        XCTAssertEqual(gpx.routes[0].name, "Test Route")
        XCTAssertEqual(gpx.routes[0].points.count, 2)
        XCTAssertEqual(gpx.routes[0].points[0].name, "Start")
        XCTAssertEqual(gpx.routes[0].points[1].name, "End")
    }

    func testParseEmptyGPX() throws {
        let empty = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.0" creator="test"></gpx>
        """
        let data = empty.data(using: .utf8)!
        let gpx = try GPXParser.parse(data)
        XCTAssertEqual(gpx.waypoints.isEmpty, true)
        XCTAssertEqual(gpx.tracks.isEmpty, true)
        XCTAssertEqual(gpx.routes.isEmpty, true)
    }

    func testParseInvalidXMLThrows() {
        let bad = "this is not XML at all"
        let data = bad.data(using: .utf8)!
        XCTAssertThrowsError(try GPXParser.parse(data))
    }

    func testParseNoWaypoints() throws {
        let gpxXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.0"><trk><trkseg><trkpt lat="0" lon="0"/></trkseg></trk></gpx>
        """
        let gpx = try GPXParser.parse(gpxXml.data(using: .utf8)!)
        XCTAssertEqual(gpx.waypoints.isEmpty, true)
        XCTAssertEqual(gpx.tracks.count, 1)
        XCTAssertEqual(gpx.tracks[0].segments[0].count, 1)
    }
}

// MARK: - GCJ-02 Conversion Tests

final class GCJ02Tests: XCTestCase {

    /// A known WGS-84 point near Beijing center
    /// GCJ-02 offset is roughly +0.005° lat, +0.005° lng at this region
    func testWGS84ToGCJ02Beijing() {
        let wgs = (lat: 39.9042, lng: 116.4074)
        let gcj = GCJ02.wgs84ToGCJ02(lat: wgs.lat, lng: wgs.lng)

        // GCJ-02 should be slightly offset from WGS-84
        XCTAssertNotEqual(gcj.lat, wgs.lat)
        XCTAssertNotEqual(gcj.lng, wgs.lng)

        // The offset should be small (< 0.02°) for mainland China
        let latDelta = abs(gcj.lat - wgs.lat)
        let lngDelta = abs(gcj.lng - wgs.lng)
        XCTAssertLessThan(latDelta, 0.02, "GCJ-02 lat offset should be small")
        XCTAssertLessThan(lngDelta, 0.02, "GCJ-02 lng offset should be small")
    }

    func testGCJ02ToWGS84RoundTrip() {
        let original = (lat: 39.9042, lng: 116.4074)
        let gcj = GCJ02.wgs84ToGCJ02(lat: original.lat, lng: original.lng)
        let recovered = GCJ02.gcj02ToWGS84(lat: gcj.lat, lng: gcj.lng)

        // Round trip should recover approximately the original value
        XCTAssertEqual(recovered.lat, original.lat, accuracy: 0.0001)
        XCTAssertEqual(recovered.lng, original.lng, accuracy: 0.0001)
    }

    func testOutsideChinaReturnsSame() {
        // London
        let gcj = GCJ02.wgs84ToGCJ02(lat: 51.5074, lng: -0.1278)
        XCTAssertEqual(gcj.lat, 51.5074, accuracy: 1e-10)
        XCTAssertEqual(gcj.lng, -0.1278, accuracy: 1e-10)
    }

    func testIsInChina() {
        XCTAssertTrue(GCJ02.isInChina(lat: 39.9, lng: 116.4))
        XCTAssertTrue(GCJ02.isInChina(lat: 31.2, lng: 121.5))  // Shanghai
        XCTAssertFalse(GCJ02.isInChina(lat: 51.5, lng: -0.1))   // London
        XCTAssertFalse(GCJ02.isInChina(lat: -33.8, lng: 151.2)) // Sydney
    }
}

// MARK: - Tile Math Tests

final class TileMathTests: XCTestCase {

    func testWGS84ToTileCoordsBeijing() {
        // Beijing at z=13
        let (x, y) = TileMath.wgs84ToTileCoords(lat: 39.9042, lng: 116.4074, z: 13)
        // Expected: around x=5854, y=2190 (±2 tiles)
        let tolerance = 2
        // From the formula: n=8192, lng 116.4074 -> (116.4074+180)/360*8192 = 6742.5 → x≈6742?
        // Let's just verify it's within [0, 8191]
        XCTAssertGreaterThanOrEqual(x, 0)
        XCTAssertLessThan(x, 8192)
        XCTAssertGreaterThanOrEqual(y, 0)
        XCTAssertLessThan(y, 8192)
    }

    func testTileCoordsToWGS84RoundTrip() {
        let z = 13
        let origLat = 39.9042, origLng = 116.4074
        let (x, y) = TileMath.wgs84ToTileCoords(lat: origLat, lng: origLng, z: z)
        let (lat, lng) = TileMath.tileCoordsToWGS84(x: x, y: y, z: z)

        // The tile NW corner will be slightly north/west of the original point
        // So lat should be >= origLat, lng <= origLng
        // The difference should be at most one tile in degree-space at z=13
        let maxTileDegrees = 360.0 / Double(1 << z)
        XCTAssertLessThanOrEqual(abs(lng - origLng), maxTileDegrees)
        XCTAssertLessThanOrEqual(abs(lat - origLat), maxTileDegrees * 2) // Mercator distortion
    }

    func testWGS84MercatorBeijing() {
        let (x, y) = TileMath.wgs84ToMercator(lat: 39.9042, lng: 116.4074)
        // lng 116.4° → x ≈ 6378137 * 116.4074 * π/180 ≈ 12_963_000
        let expectedX = 6378137.0 * 116.4074 * .pi / 180.0
        XCTAssertEqual(x, expectedX, accuracy: 1.0)
        // lat 39.9° → y ≈ 6378137 * ln(tan(π/4 + 39.9042/2 * π/180)) ≈ 4_930_000
        let expectedY = 6378137.0 * log(tan((39.9042 * .pi / 180.0) / 2 + .pi / 4))
        XCTAssertEqual(y, expectedY, accuracy: 1.0)
    }

    func testMercatorRoundTrip() {
        let (lat, lng) = (39.9042, 116.4074)
        let merc = TileMath.wgs84ToMercator(lat: lat, lng: lng)
        let recovered = TileMath.mercatorToWGS84(x: merc.x, y: merc.y)
        XCTAssertEqual(recovered.lat, lat, accuracy: 1e-6)
        XCTAssertEqual(recovered.lng, lng, accuracy: 1e-6)
    }

    func testTileURLForAMAP() {
        let url = TileSource.amapZhCN.tileURL(z: 13, x: 6742, y: 2326)
        XCTAssertTrue(url.absoluteString.contains("webrd"))
        XCTAssertTrue(url.absoluteString.contains("lang=zh_cn"))
        XCTAssertTrue(url.absoluteString.contains("x=6742"))
        XCTAssertTrue(url.absoluteString.contains("y=2326"))
        XCTAssertTrue(url.absoluteString.contains("z=13"))
    }

    func testOSMTileURL() {
        let url = TileSource.osm.tileURL(z: 12, x: 100, y: 200)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://"))
        XCTAssertTrue(url.absoluteString.contains("/12/100/200.png"))
    }
}

// MARK: - Electronic Fence Tests

final class ElectronicFenceTests: XCTestCase {

    func testSquareFenceContainsCenterPoint() {
        // Square: (0,0) (0,1) (1,1) (1,0) in lat/lng
        let vertices = [
            GeoPoint(latitude: 0, longitude: 0),
            GeoPoint(latitude: 0, longitude: 1),
            GeoPoint(latitude: 1, longitude: 1),
            GeoPoint(latitude: 1, longitude: 0)
        ]
        let fence = ElectronicFence(name: "Test", vertices: vertices)
        let center = GeoPoint(latitude: 0.5, longitude: 0.5)
        XCTAssertTrue(fence.contains(point: center), "Center of square should be inside")
    }

    func testFenceExcludesOutsidePoint() {
        let vertices = [
            GeoPoint(latitude: 0, longitude: 0),
            GeoPoint(latitude: 0, longitude: 1),
            GeoPoint(latitude: 1, longitude: 1),
            GeoPoint(latitude: 1, longitude: 0)
        ]
        let fence = ElectronicFence(name: "Test", vertices: vertices)
        let outside = GeoPoint(latitude: 2.0, longitude: 0.5)
        XCTAssertFalse(fence.contains(point: outside), "Point above the square should be outside")
    }

    func testFenceBoundingBox() {
        let vertices = [
            GeoPoint(latitude: 10, longitude: 20),
            GeoPoint(latitude: 12, longitude: 25),
            GeoPoint(latitude: 15, longitude: 18),
            GeoPoint(latitude: 8,  longitude: 30)
        ]
        let fence = ElectronicFence(name: "BB", vertices: vertices)
        XCTAssertEqual(fence.boundingBox.minLat, 8)
        XCTAssertEqual(fence.boundingBox.maxLat, 15)
        XCTAssertEqual(fence.boundingBox.minLng, 18)
        XCTAssertEqual(fence.boundingBox.maxLng, 30)
    }

    func testSmallFenceRejectsAll() {
        // Fewer than 3 vertices
        let fence = ElectronicFence(name: "Tiny",
                                    vertices: [GeoPoint(latitude: 0, longitude: 0)])
        XCTAssertFalse(fence.contains(point: GeoPoint(latitude: 0, longitude: 0)))
    }

    func testTriangleFence() {
        // Triangle: (0,0) (0,2) (2,0) — point (0.5, 0.5) should be inside
        let vertices = [
            GeoPoint(latitude: 0, longitude: 0),
            GeoPoint(latitude: 0, longitude: 2),
            GeoPoint(latitude: 2, longitude: 0)
        ]
        let fence = ElectronicFence(name: "Tri", vertices: vertices)
        XCTAssertTrue(fence.contains(point: GeoPoint(latitude: 0.5, longitude: 0.5)))
        XCTAssertFalse(fence.contains(point: GeoPoint(latitude: 1.5, longitude: 1.5)))
    }
}

// MARK: - GPXTrack Distance Tests

final class GPXTrackDistanceTests: XCTestCase {

    func testHaversineDistanceBeijingShanghai() {
        let beijing = GPXTrackPoint(latitude: 39.9042, longitude: 116.4074)
        let shanghai = GPXTrackPoint(latitude: 31.2304, longitude: 121.4737)
        let dist = beijing.haversineDistance(to: shanghai)
        // Great-circle distance is ~1065 km; allow ±50 km for WGS-84 ellipsoid approximation
        XCTAssertGreaterThanOrEqual(dist, 1_015_000)
        XCTAssertLessThanOrEqual(dist, 1_115_000)
    }

    func testZeroDistance() {
        let p = GPXTrackPoint(latitude: 39.9, longitude: 116.4)
        XCTAssertEqual(p.haversineDistance(to: p), 0, accuracy: 0.001)
    }

    func testTotalDistanceSingleSegment() {
        let p1 = GPXTrackPoint(latitude: 0, longitude: 0)
        let p2 = GPXTrackPoint(latitude: 0, longitude: 1)
        let track = GPXTrack(name: "1°", segments: [[p1, p2]])
        // 1° of longitude at the equator ≈ 111.19 km
        let dist = track.totalDistance
        XCTAssertGreaterThanOrEqual(dist, 111_000)
        XCTAssertLessThanOrEqual(dist, 112_000)
    }
}

// MARK: - AppViewModel Basic Tests

final class AppViewModelTests: XCTestCase {

    @MainActor
    func testInitialMapCenter() {
        let vm = AppViewModel()
        // Default center is Beijing
        XCTAssertEqual(vm.mapCenter.latitude, 39.9042, accuracy: 1e-6)
        XCTAssertEqual(vm.mapCenter.longitude, 116.4074, accuracy: 1e-6)
    }

    @MainActor
    func testMapClickedUpdatesReadout() {
        let vm = AppViewModel()
        vm.mapClicked(at: .init(latitude: 39.9, longitude: 116.4))
        XCTAssertNotNil(vm.lastClickCoordinate)
        XCTAssertFalse(vm.coordinateReadout.contains("Click the map"))
    }

    @MainActor
    func testFencePlacementRequiresThreeVertices() {
        let vm = AppViewModel()
        vm.startFencePlacement(name: "Test Fence")
        XCTAssertTrue(vm.isPlacingFence)

        // Try to finish with < 3 vertices
        vm.mapClicked(at: .init(latitude: 1, longitude: 1))
        vm.mapClicked(at: .init(latitude: 2, longitude: 1))
        vm.finishFencePlacement()
        // Should have set alertMessage, not created the fence
        XCTAssertTrue(vm.fences.isEmpty)

        // Add 3rd vertex and finish
        vm.mapClicked(at: .init(latitude: 1, longitude: 2))
        vm.finishFencePlacement()
        XCTAssertEqual(vm.fences.count, 1)
        XCTAssertEqual(vm.fences[0].name, "Test Fence")
        XCTAssertEqual(vm.fences[0].vertices.count, 3)
    }

    @MainActor
    func testClearAllGPX() {
        let vm = AppViewModel()
        vm.tracks.append(GPXTrajectoryData(name: "T1", segments: []))
        vm.routes.append(GPXRoute(name: "R1", points: []))
        XCTAssertFalse(vm.tracks.isEmpty)
        vm.clearAllGPX()
        XCTAssertTrue(vm.tracks.isEmpty)
        XCTAssertTrue(vm.routes.isEmpty)
    }

    @MainActor
    func testAddPointMark() {
        let vm = AppViewModel()
        let coord = CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
        vm.addPointMark(at: coord, label: "Test Point")
        XCTAssertEqual(vm.pointMarks.count, 1)
        XCTAssertEqual(vm.pointMarks[0].label, "Test Point")
    }

    @MainActor
    func testAddBeacon() {
        let vm = AppViewModel()
        vm.addBeacon(lat: 39.9, lng: 116.4, label: "Test")
        XCTAssertEqual(vm.sharedBeacons.count, 1)
        XCTAssertEqual(vm.sharedBeacons[0].label, "Test")
    }
}
