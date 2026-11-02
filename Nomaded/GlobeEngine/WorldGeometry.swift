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
}

/// One country's outline and its pre-built globe mesh (see Tools/GeoPipeline).
struct CountryShape: Sendable {
    /// ISO 3166-1 alpha-2, e.g. "IT". Empty for land that no selectable country owns.
    let code: String
    /// 0…5, assigned by the pipeline so that neighbours never share a slot.
    let colorSlot: Int
    /// Where to point the camera when the country is selected.
    let label: GeoCoordinate
    let bounds: GeoBounds
    /// Outline as (longitude, latitude), holes included. Use the even-odd rule.
    let rings: [[SIMD2<Float>]]
    /// Mesh on the unit sphere. Triangles are counter-clockwise seen from outside.
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]
}

enum WorldGeometryError: Error {
    case missingResource
    case badHeader
    case truncated
}

/// All countries, decoded from the bundled `world.nmgeo`.
/// The format is documented in Tools/GeoPipeline/Sources/GeoPipeline/WorldFileWriter.swift.
struct WorldGeometry: Sendable {
    static let magic: UInt32 = 0x4E4D_4757 // "NMGW"
    static let version: UInt16 = 2

    let countries: [CountryShape]

    /// Decodes off the main thread; the file is a few megabytes.
    static func loadBundled() async throws -> WorldGeometry {
        guard let url = Bundle.main.url(forResource: "world", withExtension: "nmgeo") else {
            throw WorldGeometryError.missingResource
        }
        return try await Task.detached(priority: .userInitiated) {
            try WorldGeometry(data: Data(contentsOf: url, options: .mappedIfSafe))
        }.value
    }

    init(data: Data) throws {
        var reader = BinaryReader(data: data)
        guard try reader.read(UInt32.self) == Self.magic, try reader.read(UInt16.self) == Self.version else {
            throw WorldGeometryError.badHeader
        }
        _ = try reader.read(UInt16.self)

        let count = try reader.readCount()
        var countries: [CountryShape] = []
        countries.reserveCapacity(count)
        for _ in 0..<count {
            countries.append(try Self.readCountry(&reader))
        }
        self.countries = countries
    }

    private static func readCountry(_ reader: inout BinaryReader) throws -> CountryShape {
        let codeLength = Int(try reader.read(UInt8.self))
        let code = String(decoding: try reader.readArray(UInt8.self, count: codeLength), as: UTF8.self)
        let colorSlot = Int(try reader.read(UInt8.self))

        let labelLongitude = try reader.readFloat()
        let labelLatitude = try reader.readFloat()
        let bounds = GeoBounds(
            minLongitude: try reader.readFloat(),
            minLatitude: try reader.readFloat(),
            maxLongitude: try reader.readFloat(),
            maxLatitude: try reader.readFloat()
        )

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
