import Foundation
import simd

struct GeoBounds: Sendable {
    var minLongitude: Float
    var minLatitude: Float
    var maxLongitude: Float
    var maxLatitude: Float

    func contains(longitude: Float, latitude: Float) -> Bool {
        longitude >= minLongitude && longitude <= maxLongitude && latitude >= minLatitude && latitude <= maxLatitude
    }

    /// Larger side, in degrees.
    var span: Float { max(maxLongitude - minLongitude, maxLatitude - minLatitude) }

    func overlaps(_ other: GeoBounds) -> Bool {
        maxLongitude >= other.minLongitude && minLongitude <= other.maxLongitude
            && maxLatitude >= other.minLatitude && minLatitude <= other.maxLatitude
    }
}

/// One country's outline and its pre-built globe mesh (see Tools/GeoPipeline).
struct CountryShape: Sendable {
    /// ISO 3166-1 alpha-2, e.g. "IT". Empty for land that no selectable country owns.
    let code: String
    /// 0…5, assigned by the pipeline so that neighbours never share a slot.
    let colorSlot: Int
    /// Its visual middle (Natural Earth's label point): fills start here and quick turns
    /// aim here. Framing a selected country uses its whole outline instead.
    let label: GeoCoordinate
    let bounds: GeoBounds
    /// Outline as (longitude, latitude), holes included (enclaves and lakes). Use the
    /// even-odd rule.
    let rings: [[SIMD2<Float>]]
    /// Mesh on the unit sphere. Triangles are counter-clockwise seen from outside.
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]
}

/// A lake the pipeline cut out of the land. The countries already show it as water; its
/// shore is kept to tell a tap on the lake from one on the ocean.
struct LakeShape: Sendable {
    let bounds: GeoBounds
    /// (longitude, latitude).
    let shore: [SIMD2<Float>]
}

/// Land some worldview draws differently (Crimea, Taiwan), and who owns it in this one.
struct DisputedRegion: Sendable {
    let code: String
    let bounds: GeoBounds
    /// (longitude, latitude), even-odd.
    let rings: [[SIMD2<Float>]]
}

/// A river, or the stretch of one inside a single country: it rises with that country.
struct RiverShape: Sendable {
    /// Index into `WorldGeometry.countries`.
    let country: Int
    /// (longitude, latitude), upstream or down.
    let points: [SIMD2<Float>]
    /// Natural Earth's rank at each point: 1 for the Amazon, up to 8 for small rivers.
    let ranks: [UInt8]
    /// How thick to draw it at each point, in hundredths (15…200): rivers widen downstream.
    let weights: [UInt8]
}

enum WorldGeometryError: Error {
    case missingResource
    case badHeader
    case truncated
}

/// All countries, the larger lakes and the rivers, decoded from the bundled `world.nmgeo`,
/// with the borders of a worldview laid over it (`world-rus.nmgeo`). The format is
/// documented in Tools/GeoPipeline/Sources/GeoPipeline/WorldFileWriter.swift.
struct WorldGeometry: Sendable {
    static let magic: UInt32 = 0x4E4D_4757 // "NMGW"
    static let version: UInt16 = 5

    let countries: [CountryShape]
    let lakes: [LakeShape]
    let rivers: [RiverShape]
    /// Disputed land with its owner in this worldview.
    let disputes: [DisputedRegion]
    /// An overlay: only the countries its worldview changes.
    let isOverlay: Bool
    /// In an overlay, the countries its worldview doesn't have.
    let removedCodes: [String]

    /// Decodes off the main thread; the file is a few megabytes.
    static func loadBundled(_ worldview: Worldview = .standard) async throws -> WorldGeometry {
        func url(_ name: String) throws -> URL {
            guard let url = Bundle.main.url(forResource: name, withExtension: "nmgeo") else { throw WorldGeometryError.missingResource }
            return url
        }
        let base = try url("world")
        let overlay = try worldview.overlayName.map(url)
        return try await Task.detached(priority: .userInitiated) {
            let world = try WorldGeometry(data: Data(contentsOf: base, options: .mappedIfSafe))
            return try overlay.map { try world.applying(WorldGeometry(data: Data(contentsOf: $0, options: .mappedIfSafe))) } ?? world
        }.value
    }

    /// The country a point belongs to when it lies on disputed land; `nil` elsewhere, where
    /// the outlines decide. Exact where the simplified outlines aren't: a city on Crimea's
    /// coast is never out at sea or across the line.
    func owner(at coordinate: GeoCoordinate) -> String? {
        let x = Float(coordinate.longitude), y = Float(coordinate.latitude)
        return disputes.first { $0.bounds.contains(longitude: x, latitude: y) && GeoMath.ringsContain($0.rings, longitude: x, latitude: y) }?.code
    }

    /// This world with a worldview's overlay laid over it: its countries replace the base's
    /// in place (new ones go last), the ones it removes go, and so do their rivers.
    func applying(_ overlay: WorldGeometry) -> WorldGeometry {
        let replacements = Dictionary(overlay.countries.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        let removed = Set(overlay.removedCodes)
        var countries: [CountryShape] = []
        var newIndex: [Int: Int] = [:]
        for (index, country) in self.countries.enumerated() where !removed.contains(country.code) {
            newIndex[index] = countries.count
            countries.append(replacements[country.code] ?? country)
        }
        let present = Set(countries.map(\.code))
        countries += overlay.countries.filter { !present.contains($0.code) }
        let overlayIndex = overlay.countries.map { country in countries.firstIndex { $0.code == country.code }! }

        let redrawn = removed.union(replacements.keys)
        let kept = rivers.compactMap { river -> RiverShape? in
            guard !redrawn.contains(self.countries[river.country].code), let index = newIndex[river.country] else { return nil }
            return RiverShape(country: index, points: river.points, ranks: river.ranks, weights: river.weights)
        }
        let added = overlay.rivers.map { river in
            RiverShape(country: overlayIndex[river.country], points: river.points, ranks: river.ranks, weights: river.weights)
        }
        return WorldGeometry(countries: countries, lakes: lakes, rivers: kept + added, disputes: overlay.disputes, isOverlay: false, removedCodes: [])
    }

    private init(countries: [CountryShape], lakes: [LakeShape], rivers: [RiverShape], disputes: [DisputedRegion], isOverlay: Bool, removedCodes: [String]) {
        self.countries = countries
        self.lakes = lakes
        self.rivers = rivers
        self.disputes = disputes
        self.isOverlay = isOverlay
        self.removedCodes = removedCodes
    }

    init(data: Data) throws {
        var reader = BinaryReader(data: data)
        guard try reader.read(UInt32.self) == Self.magic, try reader.read(UInt16.self) == Self.version else {
            throw WorldGeometryError.badHeader
        }
        isOverlay = try reader.read(UInt16.self) & 1 != 0

        let count = try reader.readCount()
        var countries: [CountryShape] = []
        countries.reserveCapacity(count)
        for _ in 0..<count {
            countries.append(try Self.readCountry(&reader))
        }
        self.countries = countries

        let lakeCount = try reader.readCount()
        var lakes: [LakeShape] = []
        lakes.reserveCapacity(lakeCount)
        for _ in 0..<lakeCount {
            let bounds = try Self.readBounds(&reader)
            lakes.append(LakeShape(bounds: bounds, shore: try reader.readArray(SIMD2<Float>.self, count: try reader.readCount())))
        }
        self.lakes = lakes

        let riverCount = try reader.readCount()
        var rivers: [RiverShape] = []
        rivers.reserveCapacity(riverCount)
        for _ in 0..<riverCount {
            let country = Int(try reader.read(UInt16.self))
            let pointCount = try reader.readCount()
            let points = try reader.readArray(SIMD2<Float>.self, count: pointCount)
            let ranks = try reader.readArray(UInt8.self, count: pointCount)
            let weights = try reader.readArray(UInt8.self, count: pointCount)
            guard country < countries.count else { throw WorldGeometryError.badHeader }
            rivers.append(RiverShape(country: country, points: points, ranks: ranks, weights: weights))
        }
        self.rivers = rivers

        let disputeCount = try reader.readCount()
        var disputes: [DisputedRegion] = []
        for _ in 0..<disputeCount {
            let code = try Self.readCode(&reader)
            let bounds = try Self.readBounds(&reader)
            let ringCount = try reader.readCount()
            var rings: [[SIMD2<Float>]] = []
            for _ in 0..<ringCount {
                rings.append(try reader.readArray(SIMD2<Float>.self, count: try reader.readCount()))
            }
            disputes.append(DisputedRegion(code: code, bounds: bounds, rings: rings))
        }
        self.disputes = disputes

        let removedCount = try reader.readCount()
        removedCodes = try (0..<removedCount).map { _ in try Self.readCode(&reader) }
    }

    private static func readCode(_ reader: inout BinaryReader) throws -> String {
        let length = Int(try reader.read(UInt8.self))
        return String(decoding: try reader.readArray(UInt8.self, count: length), as: UTF8.self)
    }

    private static func readBounds(_ reader: inout BinaryReader) throws -> GeoBounds {
        GeoBounds(
            minLongitude: try reader.readFloat(),
            minLatitude: try reader.readFloat(),
            maxLongitude: try reader.readFloat(),
            maxLatitude: try reader.readFloat()
        )
    }

    private static func readCountry(_ reader: inout BinaryReader) throws -> CountryShape {
        let code = try readCode(&reader)
        let colorSlot = Int(try reader.read(UInt8.self))

        let labelLongitude = try reader.readFloat()
        let labelLatitude = try reader.readFloat()
        let bounds = try readBounds(&reader)

        let ringCount = try reader.readCount()
        var rings: [[SIMD2<Float>]] = []
        rings.reserveCapacity(ringCount)
        for _ in 0..<ringCount {
            rings.append(try reader.readArray(SIMD2<Float>.self, count: try reader.readCount()))
        }

        let vertexCount = try reader.readCount()
        let flat = try reader.readArray(Float.self, count: vertexCount * 3)
        let vertices = (0..<vertexCount).map { SIMD3(flat[3 * $0], flat[3 * $0 + 1], flat[3 * $0 + 2]) }
        let indices = try reader.readArray(UInt32.self, count: try reader.readCount())

        return CountryShape(
            code: code,
            colorSlot: colorSlot,
            label: GeoCoordinate(latitude: Double(labelLatitude), longitude: Double(labelLongitude)),
            bounds: bounds,
            rings: rings,
            vertices: vertices,
            indices: indices
        )
    }
}

/// Sequential little-endian reader. Apple platforms are little-endian, like the file,
/// so arrays are copied straight into memory.
private struct BinaryReader {
    let data: Data
    var offset = 0

    mutating func read<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { throw WorldGeometryError.truncated }
        let start = offset
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: start, as: T.self) }
        offset += size
        return T(littleEndian: value)
    }

    mutating func readFloat() throws -> Float {
        Float(bitPattern: try read(UInt32.self))
    }

    mutating func readCount() throws -> Int {
        Int(try read(UInt32.self))
    }

    mutating func readArray<T: BitwiseCopyable>(_: T.Type, count: Int) throws -> [T] {
        let byteCount = count * MemoryLayout<T>.stride
        guard offset + byteCount <= data.count else { throw WorldGeometryError.truncated }
        let start = offset
        let data = self.data
        let array = [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            data.withUnsafeBytes { raw in
                UnsafeMutableRawBufferPointer(buffer).copyMemory(
                    from: UnsafeRawBufferPointer(rebasing: raw[start..<(start + byteCount)])
                )
            }
            initialized = count
        }
        offset += byteCount
        return array
    }
}
