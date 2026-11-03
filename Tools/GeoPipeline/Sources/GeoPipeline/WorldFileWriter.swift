import Foundation

/// Writes the `.nmgeo` file the app loads. Little-endian throughout.
/// Keep in sync with `WorldGeometry` in the app.
///
///     header   "NMGW" magic (UInt32), version UInt16, reserved UInt16, country count UInt32
///     country  code length UInt8 + UTF-8 code (empty = unclaimed land)
///              color slot UInt8 (neighbours never share a slot)
///              label lon/lat Float32 ×2
///              bounds minLon, minLat, maxLon, maxLat Float32 ×4
///              ring count UInt32; per ring: point count UInt32 + lon/lat Float32 pairs
///              vertex count UInt32 + xyz Float32 triples (unit sphere)
///              index count UInt32 + UInt32 indices (CCW seen from outside)
///     lakes    count UInt32; per lake: bounds Float32 ×4, then its shore as point count
///              UInt32 + lon/lat Float32 pairs. The countries already have them cut out;
///              these are only for telling a tap on a lake from one on the ocean.
struct BuiltCountry {
    let code: String
    let colorSlot: Int
    let label: GeoPoint
    let rings: [[GeoPoint]]
    let vertices: [SIMD3<Double>]
    let indices: [UInt32]
}

enum WorldFileWriter {
    static let magic: UInt32 = 0x4E4D_4757 // "NMGW"
    static let version: UInt16 = 3

    static func encode(_ countries: [BuiltCountry], lakes: [[GeoPoint]]) -> Data {
        var data = Data()
        append(magic, to: &data)
        append(version, to: &data)
        append(UInt16(0), to: &data)
        append(UInt32(countries.count), to: &data)

        for country in countries {
            let code = Array(country.code.utf8)
            append(UInt8(code.count), to: &data)
            data.append(contentsOf: code)
            append(UInt8(country.colorSlot), to: &data)

            append(Float(country.label.x), to: &data)
            append(Float(country.label.y), to: &data)

            let points = country.rings.flatMap { $0 }
            append(Float(points.map(\.x).min() ?? 0), to: &data)
            append(Float(points.map(\.y).min() ?? 0), to: &data)
            append(Float(points.map(\.x).max() ?? 0), to: &data)
            append(Float(points.map(\.y).max() ?? 0), to: &data)

            append(UInt32(country.rings.count), to: &data)
            for ring in country.rings {
                append(UInt32(ring.count), to: &data)
                for point in ring {
                    append(Float(point.x), to: &data)
                    append(Float(point.y), to: &data)
                }
            }

            append(UInt32(country.vertices.count), to: &data)
            for v in country.vertices {
                append(Float(v.x), to: &data)
                append(Float(v.y), to: &data)
                append(Float(v.z), to: &data)
            }

            append(UInt32(country.indices.count), to: &data)
            for index in country.indices { append(index, to: &data) }
        }

        append(UInt32(lakes.count), to: &data)
        for shore in lakes {
            append(Float(shore.map(\.x).min() ?? 0), to: &data)
            append(Float(shore.map(\.y).min() ?? 0), to: &data)
            append(Float(shore.map(\.x).max() ?? 0), to: &data)
            append(Float(shore.map(\.y).max() ?? 0), to: &data)
            append(UInt32(shore.count), to: &data)
            for point in shore {
                append(Float(point.x), to: &data)
                append(Float(point.y), to: &data)
            }
        }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: Float, to data: inout Data) {
        append(value.bitPattern, to: &data)
    }
}
