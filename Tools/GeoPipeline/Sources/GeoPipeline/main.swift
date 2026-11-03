import Foundation

// Natural Earth GeoJSON → Nomaded globe geometry (.nmgeo).
// See Tools/GeoPipeline/README.md for the exact command and data source.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: GeoPipeline <input.geojson> <output.nmgeo> [--tolerance degrees]")
    exit(1)
}

let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
// ~2 km. At the app's maximum zoom that is about 3 points on screen, too little to notice on a coastline.
var tolerance = 0.02
if let flag = arguments.firstIndex(of: "--tolerance"), flag + 1 < arguments.count, let value = Double(arguments[flag + 1]) {
    tolerance = value
}

let started = Date()
let features = try GeoJSONReader.read(input)
let originals = CountryAssembler.assemble(features)
let countries = TopologySimplifier.simplify(originals, tolerance: tolerance)
// Six slots, matching the six candy colors in the app's palette.
let colorSlots = ColorAssigner.assign(originals, slotCount: 6)

var built: [BuiltCountry] = []
var fallbacks = 0
for (index, (country, original)) in zip(countries, originals).enumerated() {
    var builder = SphereMeshBuilder(maxEdgeDegrees: 1.5, densifyStepDegrees: 0.75)
    for (polygon, originalPolygon) in zip(country.polygons, original.polygons) {
        builder.add(polygon, original: originalPolygon)
    }
    fallbacks += builder.fallbackCount
    built.append(BuiltCountry(
        code: country.code,
        colorSlot: colorSlots[index],
        label: country.label,
        rings: builder.rings,
        vertices: builder.vertices,
        indices: builder.indices
    ))
}

let data = WorldFileWriter.encode(built)
try data.write(to: output)

let ringPoints = built.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }
let vertices = built.reduce(0) { $0 + $1.vertices.count }
let triangles = built.reduce(0) { $0 + $1.indices.count / 3 }
print("""
countries: \(built.count) (selectable: \(built.filter { !$0.code.isEmpty }.count))
source vertices: \(features.reduce(0) { $0 + $1.vertexCount }), ring points after simplify+densify: \(ringPoints)
mesh: \(vertices) vertices, \(triangles) triangles
polygons rebuilt from the unsimplified outline: \(fallbacks)
file: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s
""")
