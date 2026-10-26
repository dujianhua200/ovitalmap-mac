import Foundation

// MARK: - GPX XML Parser (Foundation XMLParser)

enum GPXParseError: Error, LocalizedError {
    case invalidXML(String)
    case noGPXRoot

    var errorDescription: String? {
        switch self {
        case .invalidXML(let msg): return "Invalid GPX: \(msg)"
        case .noGPXRoot:          return "Missing <gpx> root element"
        }
    }
}

enum GPXParser {

    /// Parse GPX 1.0/1.1 XML data into a GPXFile model.
    static func parse(_ data: Data) throws -> GPXFile {
        let handler = _GPXHandler()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        guard parser.parse() else {
            let msg = parser.parserError?.localizedDescription ?? "unknown parse error"
            throw GPXParseError.invalidXML(msg)
        }
        guard let gpx = handler.result else {
            throw GPXParseError.noGPXRoot
        }
        return gpx
    }
}

// MARK: - Incremental XML delegate

private final class _GPXHandler: NSObject, XMLParserDelegate {

    private(set) var result: GPXFile?

    private var gpxVersion = "1.0"
    private var gpxCreator: String?
    private var waypoints = [GPXWaypoint]()
    private var tracks    = [GPXTrack]()
    private var routes    = [GPXRoute]()

    private enum Tag { case gpx, wpt, trk, trkseg, trkpt, rte, rtept, name, ele, time, other }
    private var stack: [Tag] = []
    private var nameOwner: Tag?
    private var textBuf = ""
    private var activeTrkSeg = 0

    private func top() -> Tag? { stack.last }

    // MARK: XMLParserDelegate

    /// 去掉命名空间前缀，兼容 `<gpx:trk>` 这类写法。
    private static func localName(_ name: String) -> String {
        guard let colon = name.firstIndex(of: ":") else { return name }
        return String(name[name.index(after: colon)...])
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        textBuf = ""
        switch Self.localName(elementName) {
        case "gpx":
            gpxVersion = attributes["version"] ?? "1.0"
            gpxCreator = attributes["creator"]
            stack.append(.gpx)
        case "wpt":
            waypoints.append(GPXWaypoint(
                latitude: Double(attributes["lat"] ?? "") ?? 0,
                longitude: Double(attributes["lon"] ?? "") ?? 0))
            stack.append(.wpt)
        case "trk":
            tracks.append(GPXTrack(name: nil, segments: []))
            stack.append(.trk)
        case "trkseg":
            if tracks.count > 0 {
                tracks[tracks.count - 1].segments.append([])
                activeTrkSeg = tracks[tracks.count - 1].segments.count - 1
            }
            stack.append(.trkseg)
        case "trkpt":
            if let ti = lastTrkIndex(), ti >= 0,
               activeTrkSeg < tracks[ti].segments.count {
                let pt = GPXTrackPoint(
                    latitude: Double(attributes["lat"] ?? "") ?? 0,
                    longitude: Double(attributes["lon"] ?? "") ?? 0)
                tracks[ti].segments[activeTrkSeg].append(pt)
            }
            stack.append(.trkpt)
        case "rte":
            routes.append(GPXRoute(name: nil, points: []))
            stack.append(.rte)
        case "rtept":
            if let ri = lastRteIndex(), ri >= 0 {
                routes[ri].points.append(GPXWaypoint(
                    latitude: Double(attributes["lat"] ?? "") ?? 0,
                    longitude: Double(attributes["lon"] ?? "") ?? 0))
            }
            stack.append(.rtept)
        case "name":
            nameOwner = top()
            stack.append(.name)
        case "ele":
            stack.append(.ele)
        case "time":
            stack.append(.time)
        default:
            // 未知元素也要入栈，否则 didEndElement 的 removeLast 会把父元素弹掉，
            // 导致 <metadata>/<extensions> 之后的解析上下文错位。
            stack.append(.other)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // Only accumulate text for the leaf text elements we care about.
        switch top() {
        case .name, .ele, .time:
            textBuf += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock, encoding: .utf8) else { return }
        switch top() {
        case .name, .ele, .time:
            textBuf += text
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = textBuf.trimmingCharacters(in: .whitespacesAndNewlines)
        textBuf = ""

        switch Self.localName(elementName) {
        case "name":
            applyName(owner: nameOwner, text: text)
        case "ele":
            applyElevation(text: text)
        case "time":
            applyTime(text: text)
        case "gpx":
            result = GPXFile(version: gpxVersion, creator: gpxCreator,
                              waypoints: waypoints, tracks: tracks, routes: routes)
        default:
            break
        }
        if !stack.isEmpty { stack.removeLast() }
    }

    // MARK: helpers

    private func lastTrkIndex() -> Int? {
        tracks.isEmpty ? nil : tracks.count - 1
    }
    private func lastRteIndex() -> Int? {
        routes.isEmpty ? nil : routes.count - 1
    }

    private func applyName(owner: Tag?, text: String) {
        guard !text.isEmpty else { return }
        switch owner {
        case .wpt:
            if !waypoints.isEmpty { waypoints[waypoints.count - 1].name = text }
        case .trk:
            if !tracks.isEmpty { tracks[tracks.count - 1].name = text }
        case .rte:
            if !routes.isEmpty { routes[routes.count - 1].name = text }
        case .rtept:
            if let ri = lastRteIndex(), !routes[ri].points.isEmpty {
                routes[ri].points[routes[ri].points.count - 1].name = text
            }
        default:
            break
        }
    }

    private func applyElevation(text: String) {
        guard let v = Double(text) else { return }
        if let ti = lastTrkIndex(), ti >= 0,
           activeTrkSeg < tracks[ti].segments.count,
           !tracks[ti].segments[activeTrkSeg].isEmpty {
            let pi = tracks[ti].segments[activeTrkSeg].count - 1
            tracks[ti].segments[activeTrkSeg][pi].elevation = v
        }
    }

    private func applyTime(text: String) {
        guard let d = Self.parseGPXDate(text) else { return }
        if let ti = lastTrkIndex(), ti >= 0,
           activeTrkSeg < tracks[ti].segments.count,
           !tracks[ti].segments[activeTrkSeg].isEmpty {
            let pi = tracks[ti].segments[activeTrkSeg].count - 1
            tracks[ti].segments[activeTrkSeg][pi].time = d
        }
    }

    static func parseGPXDate(_ s: String) -> Date? {
        // GPX 1.0 / 1.1: 2024-01-01T00:00:00Z (T separator + 'Z' UTC)
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime]
        if let d = f1.date(from: s) { return d }

        // GPX 1.1 with fractional seconds: 2024-01-01T00:00:00.123Z
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withFractionalSeconds, .withTimeZone]
        if let d = f2.date(from: s) { return d }

        // No timezone
        let f3 = ISO8601DateFormatter()
        f3.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        if let d = f3.date(from: s) { return d }

        // Plain date
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(abbreviation: "UTC")
        return df.date(from: s)
    }
}
