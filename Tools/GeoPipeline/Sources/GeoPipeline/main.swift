import Foundation

// Natural Earth GeoJSON → Nomaded globe geometry (.nmgeo); with --catalog, the country
// catalog (countries.json) the statistics read; with --places and --cities, the city list
// (cities.json) the city search reads.
// See Tools/GeoPipeline/README.md for the exact command and data source.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: GeoPipeline <input.geojson> <output.nmgeo> [--lakes lakes.geojson] [--rivers rivers.geojson] [--catalog countries.json] [--places places.geojson --cities cities.json] [--tolerance degrees]")
    exit(1)
}

let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
// ~2 km. At the app's maximum zoom that is about 3 points on screen, too little to notice on a coastline.
var tolerance = 0.02
if let flag = arguments.firstIndex(of: "--tolerance"), flag + 1 < arguments.count, let value = Double(arguments[flag + 1]) {
    tolerance = value
}

func fileArgument(_ flag: String) -> URL? {
    arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
}
let catalogOutput = fileArgument("--catalog")
let placesInput = fileArgument("--places")
let citiesOutput = fileArgument("--cities")
let lakesInput = fileArgument("--lakes")
let riversInput = fileArgument("--rivers")

let started = Date()
let features = try GeoJSONReader.read(input)
let originals = CountryAssembler.assemble(features)
// The globe's land, with the lakes taken out. Colors, the catalog and the city list keep
// working from the whole countries.
var shaped = originals
var shores: [[GeoPoint]] = []
var rawShores: [[GeoPoint]] = []
var lakeSummary = ""
if let lakesInput {
    let lakes = LakeCutter.select(try GeoJSONReader.readLakes(lakesInput))
    let result = LakeCutter.cut(originals, lakes: lakes)
    shaped = result.countries
    rawShores = result.shores
    shores = result.shores.map { TopologySimplifier.simplifyClosed($0, tolerance: tolerance) }
    lakeSummary = "\nlakes: \(lakes.count) selected, \(shores.count) cut into land"
    if !result.skipped.isEmpty { lakeSummary += ", left as land: \(result.skipped.joined(separator: ", "))" }
}
let countries = TopologySimplifier.simplify(shaped, tolerance: tolerance)
// Six slots, matching the six candy colors in the app's palette.
let colorSlots = ColorAssigner.assign(originals, slotCount: 6)

var built: [BuiltCountry] = []
var fallbacks = 0
for (index, (country, original)) in zip(countries, shaped).enumerated() {
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

var rivers: [RiverBuilder.Built] = []
if let riversInput {
    // Lakes are matched against their unsimplified shores, as cut.
    let cutShores = lakesInput == nil ? [] : rawShores
    rivers = RiverBuilder.build(try GeoJSONReader.readRivers(riversInput), countries: countries, shores: cutShores, tolerance: tolerance)
    lakeSummary += "\nrivers: \(rivers.count) lines, \(rivers.reduce(0) { $0 + $1.points.count }) points"
}

let data = WorldFileWriter.encode(built, lakes: shores, rivers: rivers)
try data.write(to: output)

var catalogSummary = ""
if let catalogOutput {
    // Areas come from the unsimplified outlines.
    let entries = try CountryCatalog.entries(originals)
    try CountryCatalog.encode(entries).write(to: catalogOutput)
    catalogSummary = "\ncatalog: \(entries.count) places, \(entries.filter(\.sovereign).count) countries"
}
if let placesInput, let citiesOutput {
    let cities = try CityCatalogBuilder.entries(placesInput, countries: Set(originals.map(\.code).filter { !$0.isEmpty }))
    let data = try CityCatalogBuilder.encode(cities)
    try data.write(to: citiesOutput)
    catalogSummary += "\ncities: \(cities.count), \(cities.filter(\.capital).count) capitals, "
        + ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
}

let ringPoints = built.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }
let vertices = built.reduce(0) { $0 + $1.vertices.count }
let triangles = built.reduce(0) { $0 + $1.indices.count / 3 }
print("""
countries: \(built.count) (selectable: \(built.filter { !$0.code.isEmpty }.count))
source vertices: \(features.reduce(0) { $0 + $1.vertexCount }), ring points after simplify+densify: \(ringPoints)
mesh: \(vertices) vertices, \(triangles) triangles
polygons rebuilt from the unsimplified outline: \(fallbacks)
file: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s\(lakeSummary)\(catalogSummary)
""")
