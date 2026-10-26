import Foundation
import CoreLocation

// MARK: - GPX XML Parser (ElementTree-based, no external deps)

enum GPXParseError: Error, LocalizedError {
    case invalidXML
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .invalidXML: return "Invalid or malformed GPX file"
        case .unsupportedVersion: return "Unsupported GPX version"
        }
    }
}

enum GPXParser {

    /// Parse GPX XML data into a GPXFile model
    static func parse(_ data: Data) throws -> GPXFile {
        // 1. Validate root
        guard let root = try parseRootElement(data) else {
            throw GPXParseError.invalidXML
        }

        // 2. Read attributes
        let version = root.attributes["version"] ?? "1.0"
        let creator = root.attributes["creator"]

        // 3. Parse child elements
        var waypoints = [GPXWaypoint]()
        var tracks = [GPXTrack]()
        var routes = [GPXRoute]()

        for element in root.children {
            switch element.name {
            case "wpt":
                if let wpt = parseWaypoint(element) {
                    waypoints.append(wpt)
                }
            case "trk":
                if let trk = parseTrack(element) {
                    tracks.append(trk)
                }
            case "rte":
                if let rte = parseRoute(element) {
                    routes.append(rte)
                }
            default:
                break
            }
        }

        return GPXFile(version: version, creator: creator,
                       waypoints: waypoints, tracks: tracks, routes: routes)
    }

    // MARK: - Private XML helpers (lightweight DOM)

    /// Minimal XML element representation
    private struct XMLElement {
        let name: String
        let attributes: [String: String]
        let children: [XMLElement]
        let text: String?
    }

    /// Parse the root <gpx> element
    private static func parseRootElement(_ data: Data) throws -> XMLElement? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        return parseElement(xml: xml, rootOnly: true)
    }

    /// A very small recursive-descent XML parser sufficient for GPX 1.0/1.1
    private static func parseElement(xml: String, rootOnly: Bool = false) -> XMLElement? {
        // Trim BOM / whitespace
        var src = xml.filter { $0 != "\u{FEFF}" }
        guard let openTagStart = src.firstIndex(of: "<") else { return nil }
        src = String(src[openTagStart...])

        guard let root = tryParseElement(from: &src) else { return nil }
        return root
    }

    private static func tryParseElement(from source: inout String) -> XMLElement? {
        guard source.hasPrefix("<"), let tagEnd = source.firstIndex(of: ">") else { return nil }
        let tagContent = source[..<tagEnd]
        let tagString = String(tagContent.dropFirst())

        // Determine element name
        let nameEnd = tagString.firstIndex(where: { $0 == " " || $0 == "/" }) ?? tagString.endIndex
        let name = String(tagString[..<nameEnd])
        var attrs = [String: String]()
        var selfClosing = tagString.hasSuffix("/>")

        if selfClosing {
            // Self-closing: <tag attr="val"/>
            let attrsString = String(tagString[..<tagString.index(before: tagString.endIndex)])
            parseAttributes(attrsString, into: &attrs)
            source.removeFirst(tagString.count + 1)
            return XMLElement(name: name, attributes: attrs, children: [], text: nil)
        }

        // Normal opening tag: <tag attr="val">
        parseAttributes(tagString, into: &attrs)
        source.removeFirst(tagString.count + 1)

        // Collect children until </name>
        var children = [XMLElement]()
        var textBuffer = ""
        let closeTag = "</\(name)>"

        while !source.isEmpty {
            if source.hasPrefix(closeTag) {
                source.removeFirst(closeTag.count)
                break
            }
            if source.hasPrefix("<!") || source.hasPrefix("<!--") {
                // Comment / CDATA: skip
                let endIdx = source.firstIndex(of: ">") ?? source.endIndex
                source.removeFirst(source.distance(from: source.startIndex, to: endIdx) + 1)
                continue
            }
            if source.hasPrefix("<") {
                guard let child = tryParseElement(from: &source) else { break }
                children.append(child)
            } else {
                // Plain text
                let nextTag = source.firstIndex(of: "<")
                let textChunk: String
                if let end = nextTag {
                    textChunk = String(source[..<end])
                } else {
                    textChunk = source
                }
                source = String(source.dropFirst(textChunk.count))
                textBuffer += textChunk
            }
        }

        let trimmedText = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        return XMLElement(name: name, attributes: attrs, children: children,
                          text: trimmedText.isEmpty ? nil : trimmedText)
    }

    /// Parse XML attributes from a tag string like: `gpx version="1.0" creator="x"`
    private static func parseAttributes(_ tagString: String, into attrs: inout [String: String]) {
        let parts = tagString.components(separatedBy: " ").filter { !$0.isEmpty }
        for part in parts.dropFirst() {
            guard let eqIdx = part.firstIndex(of: "=") else { continue }
            let key = String(part[..<eqIdx])
            let valPart = String(part[part.index(after: eqIdx)...])
            let val = valPart
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            attrs[key] = val
        }
    }

    /// Safe double parse
    private static func double(_ s: String?) -> Double? {
        guard let s = s else { return nil }
        return Double(s)
    }

    // MARK: - Element parsers

    private static func parseWaypoint(_ el: XMLElement) -> GPXWaypoint? {
        guard let lat = double(el.attributes["lat"]),
              let lon = double(el.attributes["lon"]) else { return nil }
        let name = el.children.first { $0.name == "name" }?.text
        return GPXWaypoint(latitude: lat, longitude: lon, name: name)
    }

    private static func parseTrack(_ el: XMLElement) -> GPXTrack? {
        let name = el.children.first { $0.name == "name" }?.text
        var segments = [[GPXTrackPoint]]()

        for segEl in el.children where segEl.name == "trkseg" {
            var points = [GPXTrackPoint]()
            for pEl in segEl.children where pEl.name == "trkpt" {
                guard let lat = double(pEl.attributes["lat"]),
                      let lon = double(pEl.attributes["lon"]) else { continue }
                let elev = pEl.children.first { $0.name == "ele" }
                    .flatMap { double($0.text) }
                let timeStr = pEl.children.first { $0.name == "time" }?.text
                let time = timeStr.flatMap { parseGPXDate($0) }
                points.append(GPXTrackPoint(latitude: lat, longitude: lon,
                                            elevation: elev, time: time))
            }
            segments.append(points)
        }
        return GPXTrack(name: name, segments: segments)
    }

    private static func parseRoute(_ el: XMLElement) -> GPXRoute? {
        let name = el.children.first { $0.name == "name" }?.text
        var points = [GPXWaypoint]()
        for pEl in el.children where pEl.name == "rtept" {
            guard let lat = double(pEl.attributes["lat"]),
                  let lon = double(pEl.attributes["lon"]) else { continue }
            let name = pEl.children.first { $0.name == "name" }?.text
            points.append(GPXWaypoint(latitude: lat, longitude: lon, name: name))
        }
        return GPXRoute(name: name, points: points)
    }

    /// Parse ISO 8601 dates as used in GPX 1.1 / GPX 1.0
    private static func parseGPXDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        // Fall back: GPX 1.0 uses "yyyy-MM-ddTHH:mm:ssZ"
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        return fallback.date(from: s)
    }
}
