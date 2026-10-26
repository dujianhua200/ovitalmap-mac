import Foundation

// MARK: - GPX XML Parser

enum GPXParseError: Error, LocalizedError {
    case invalidXML
    case noRootElement
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .invalidXML: return "Invalid or malformed GPX file"
        case .noRootElement: return "Missing <gpx> root element"
        case .unsupportedVersion: return "Unsupported GPX version"
        }
    }
}

enum GPXParser {

    /// Parse GPX XML data into a GPXFile model using Foundation's XMLParser.
    static func parse(_ data: Data) throws -> GPXFile {
        let parser = XMLParser(data: data)
        let handler = GPXParseHandler()
        parser.delegate = handler
        guard parser.parse() else {
            if let err = parser.parserError {
                throw GPXParseError.invalidXML
            }
            throw GPXParseError.noRootElement
        }

        guard let gpx = handler.gpxFile else {
            // XML parsed but no <gpx> root — treat as invalid
            throw GPXParseError.noRootElement
        }
        return gpx
    }
}

/// Incremental XMLParser delegate that builds the GPX model.
private final class GPXParseHandler: NSObject, XMLParserDelegate {
    private var elementStack = [String]()
    private var attrStack = [[String: String]]()
    private var currentText = ""

    // GPX model accumulators
    private var gpxVersion = "1.0"
    private var gpxCreator: String?
    private var waypoints = [GPXWaypoint]()
    private var tracks = [GPXTrack]()
    private var routes = [GPXRoute]()

    // Context
    private var currentWaypoint: GPXWaypoint?
    private var currentTrack: GPXTrack?
    private var currentTrackSeg: [GPXTrackPoint] = []
    private var currentRoute: GPXRoute?
    private var currentTextTag: String?

    var gpxFile: GPXFile?

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qName: String?, attributes: [String: String]) {
        elementStack.append(elementName)
        attrStack.append(attributes)
        currentText = ""
        currentTextTag = elementName

        switch elementName {
        case "gpx":
            gpxVersion = attributes["version"] ?? "1.0"
            gpxCreator = attributes["creator"]
        case "wpt":
            currentWaypoint = GPXWaypoint(
                latitude: (attributes["lat"] as? String).flatMap(Double.init) ?? 0,
                longitude: (attributes["lon"] as? String).flatMap(Double.init) ?? 0
            )
        case "trk":
            currentTrack = GPXTrack(name: nil, segments: [])
        case "trkseg":
            currentTrackSeg = []
        case "trkpt":
            let p = GPXTrackPoint(
                latitude: (attributes["lat"] as? String).flatMap(Double.init) ?? 0,
                longitude: (attributes["lon"] as? String).flatMap(Double.init) ?? 0,
                elevation: nil, time: nil
            )
            // Stash on the track segment; ele/time fill in on child close
            if let t = currentTrack {
                var segs = t.segments
                if segs.isEmpty { segs.append([]) }
                segs[segs.count - 1].append(p)
                currentTrack = GPXTrack(name: t.name, segments: segs)
            }
        case "rte":
            currentRoute = GPXRoute(name: nil, points: [])
        case "rtept":
            currentRoute?.points.append(GPXWaypoint(
                latitude: (attributes["lat"] as? String).flatMap(Double.init) ?? 0,
                longitude: (attributes["lon"] as? String).flatMap(Double.init) ?? 0
            ))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "name":
            fillName(trimmed)
        case "ele":
            fillElevation(trimmed)
        case "time":
            fillTime(trimmed)
        case "trkseg":
            if let t = currentTrack, !currentTrackSeg.isEmpty {
                // Rebuild with the completed segment
                currentTrack = GPXTrack(name: t.name,
                                         segments: t.segments + [currentTrackSeg])
            }
            currentTrackSeg = []
        case "trk":
            if let t = currentTrack { tracks.append(t) }
            currentTrack = nil
        case "wpt":
            if let w = currentWaypoint { waypoints.append(w) }
            currentWaypoint = nil
        case "rte":
            if let r = currentRoute { routes.append(r) }
            currentRoute = nil
        case "gpx":
            gpxFile = GPXFile(version: gpxVersion, creator: gpxCreator,
                               waypoints: waypoints, tracks: tracks, routes: routes)
        default:
            break
        }

        if !elementStack.isEmpty { elementStack.removeLast() }
        if !attrStack.isEmpty { attrStack.removeLast() }
    }

    // MARK: - Fill helpers

    /// The <name> element belongs to whichever element currently encloses it.
    private func fillName(_ text: String) {
        guard !text.isEmpty else { return }
        // elementStack (before pop) looks like [..., "wpt", "name"] or [..., "trk", "name"]
        let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : ""
        switch parent {
        case "wpt":
            currentWaypoint?.name = text
        case "trk":
            currentTrack = GPXTrack(name: text, segments: currentTrack?.segments ?? [])
        case "rte":
            currentRoute?.name = text
        default:
            break
        }
    }

    private func fillElevation(_ text: String) {
        guard let value = Double(text) else { return }
        guard let t = currentTrack else { return }
        var segs = t.segments
        guard !segs.isEmpty, !segs[segs.count - 1].isEmpty else { return }
        let idx = segs[segs.count - 1].count - 1
        segs[segs.count - 1][idx].elevation = value
        currentTrack = GPXTrack(name: t.name, segments: segs)
    }

    private func fillTime(_ text: String) {
        guard let date = Self.parseGPXDate(text) else { return }
        guard let t = currentTrack else { return }
        var segs = t.segments
        guard !segs.isEmpty, !segs[segs.count - 1].isEmpty else { return }
        let idx = segs[segs.count - 1].count - 1
        segs[segs.count - 1][idx].time = date
        currentTrack = GPXTrack(name: t.name, segments: segs)
    }

    /// Parse ISO 8601 dates as used in GPX 1.0 / 1.1.
    static func parseGPXDate(_ s: String) -> Date? {
        // GPX 1.1: "2024-01-01T00:00:00Z" or with fractional seconds
        var formatters = [
            ISO8601DateFormatter(),
            ISO8601DateFormatter(),
            ISO8601DateFormatter()
        ]
        formatters[0].formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        formatters[1].formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withFractionalSeconds, .withTimeZone]
        formatters[2].formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withFractionalSeconds]
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        // Last resort: simple date-only
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(abbreviation: "UTC")
        return df.date(from: s)
    }
}
