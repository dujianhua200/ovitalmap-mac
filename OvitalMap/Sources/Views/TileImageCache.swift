import Foundation

/// Tile cache: stores downloaded tile data by coordinate key,
/// with size-based eviction and actor-based thread safety.
actor TileImageCache {
    static let shared = TileImageCache()

    private var cache: [String: Data] = [:]
    private let maxBytes = 32 * 1024 * 1024   // 32 MB
    private var totalBytes = 0

    private func key(z: Int, x: Int, y: Int) -> String {
        "\(z)_\(x)_\(y)"
    }

    /// Get cached tile data for a coordinate.
    func get(z: Int, x: Int, y: Int) -> Data? {
        cache[key(z: z, x: x, y: y)]
    }

    /// Store tile data in cache, evicting oldest entries if over capacity.
    @discardableResult
    func put(z: Int, x: Int, y: Int, data: Data) -> Bool {
        let k = key(z: z, x: x, y: y)
        if let existing = cache[k] {
            totalBytes -= existing.count
        }
        cache[k] = data
        totalBytes += data.count
        while totalBytes > maxBytes, let k = cache.keys.first {
            totalBytes -= cache[k]?.count ?? 0
            cache[k] = nil
        }
        return true
    }

    /// Remove all cached data.
    func clear() {
        cache.removeAll()
        totalBytes = 0
    }

    /// Number of cached tiles.
    var count: Int { cache.count }
}
