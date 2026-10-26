# OvitalMap — macOS Rebuild

An open-source macOS rebuild of **OvitalMap (奥维互动地图 / omap)**, the GPS / offline map
client developed by Beijing Ovital Software. The original is a 27 MB Windows MFC + CEF
binary (`111.exe`); this project re-implements its core functionality natively on macOS
using SwiftUI, with **AMap public tiles** (GCJ-02, key-free public tile servers).

## Features

| Feature | Status |
|---|---|
| Tile map viewer (AMap zh-CN / EN / JA, OSM) | ✅ |
| Click-to-read WGS-84 & GCJ-02 coordinates | ✅ |
| GPX import (tracks, routes, waypoints) | ✅ |
| GPS track rendering + Haversine distance | ✅ |
| Electronic fence polygon (click to draw, point-in-polygon test) | ✅ |
| Location sharing beacons (named markers) | ✅ |
| Layer panel (tracks / routes / points / fences / beacons) | ✅ |
| GCJ-02 ⇄ WGS-84 coordinate conversion | ✅ |
| Tile URL generator (shard rotation, deterministic per tile) | ✅ |

## Tech Stack

- **Swift 5.10 / SwiftUI** — native macOS (Deployment Target 13.0)
- **CoreLocation** — coordinate types
- **AMap public tile servers** (`webrd0{1-4}.is.autonavi.com`) — no API key required
- **Custom lightweight GPX 1.0/1.1 XML parser** — no external dependencies
- **XcodeGen** — declarative project generation

## Project Layout

```
OvitalMap/
├── project.yml              # XcodeGen manifest
├── Sources/
│   ├── OvitalMapApp.swift   # @main entry
│   ├── Models/
│   │   ├── GeoModels.swift          # Coordinate systems, GPX, fence models
│   │   ├── GPXParser.swift          # Lightweight GPX XML parser
│   │   ├── TileURLBuilder.swift     # AMap/OSM tile URL + Web Mercator math
│   │   └── AppViewModel.swift       # @MainActor observable app state
│   └── Views/
│       ├── AMapTileView.swift       # Tile fetch + render
│       ├── ToolbarView.swift        # Top toolbar
│       ├── SidePanelView.swift      # Right panel (tabs)
│       ├── MapCanvasView.swift      # Tile + overlay composite
│       └── TileImageCache.swift     # Actor-based tile cache
└── Tests/
    └── OvitalMapTests.swift         # Unit tests (GCJ-02, GPX, fences, tile math)
```

## Building Locally

```bash
# 1. Install XcodeGen
brew install xcodegen

# 2. Generate the Xcode project
cd OvitalMap
xcodegen generate

# 3. Build + run tests
xcodebuild test \
  -project OvitalMap.xcodeproj \
  -scheme OvitalMapTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Or open `OvitalMap.xcodeproj` in Xcode and hit **Run**.

## GitHub CI

`.github/workflows/build-test.yml` runs on every push/PR:

1. `brew install xcodegen`
2. `xcodegen generate` → produces `OvitalMap.xcodeproj`
3. `xcodebuild build -configuration Release`
4. `xcodebuild test`
5. Uploads the resulting `.app` as a workflow artifact

## Tile Source Notes

AMap public tiles use **GCJ-02** coordinates (the Chinese "Mars" offset applied to
WGS-84). The tile server returns pixels in the standard Web Mercator grid; to
overlay WGS-84 GPS data on top of AMap tiles, convert the GPS coordinates
with `GCJ02.wgs84ToGCJ02()` before projecting to screen space.

Tile URL pattern:
```
https://webrd0{1-4}.is.autonavi.com/appmaptile
  ?lang=zh_cn&size=256&scale=1&style=7&x={x}&y={y}&z={z}
```

Shard rotation is deterministic per tile (`(x * y * 31) % 4 + 1`) so the cache
key is stable but hostnames are spread across four mirrors.

## License

MIT
