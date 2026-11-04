import Foundation

// Natural Earth GeoJSON → Nomaded globe geometry (.nmgeo); with --admin1, an overlay per
// App Store worldview next to it (world-rus.nmgeo, see Worldview.swift); with --catalog, the country
// catalog (countries.json) the statistics read; with --places and --cities, the city list
// (cities.json) the city search reads.
// See Tools/GeoPipeline/README.md for the exact command and data source.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: GeoPipeline <input.geojson> <output.nmgeo> [--lakes lakes.geojson] [--rivers rivers.geojson] [--admin1 admin1.geojson] [--catalog countries.json] [--places places.geojson --cities cities.json] [--tolerance degrees]")
    exit(1)
}

let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
// ~2 km. At the app's maximum zoom that is about 3 points on screen, too little to notice on a coastline.
let tolerance = arguments.firstIndex(of: "--tolerance").flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil } ?? 0.02

func fileArgument(_ flag: String) -> URL? {
    arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
}
let catalogOutput = fileArgument("--catalog")
let placesInput = fileArgument("--places")
let citiesOutput = fileArgument("--cities")
let lakesInput = fileArgument("--lakes")
let riversInput = fileArgument("--rivers")

let admin1Input = fileArgument("--admin1")

let started = Date()
let features = try GeoJSONReader.read(input)
let originals = CountryAssembler.assemble(features)
// Six slots, matching the six candy colors in the app's palette. Worldviews keep each
// country's slot, so Russia is the same color whatever the App Store region.
let colorSlots = ColorAssigner.assign(originals, slotCount: 6)
let slotByCode = Dictionary(zip(originals.map(\.code), colorSlots), uniquingKeysWith: { first, _ in first })
let lakes = try lakesInput.map { LakeCutter.select(try GeoJSONReader.readLakes($0)) }
let riverSources = try riversInput.map { try GeoJSONReader.readRivers($0) }
let regions = try admin1Input.map { try GeoJSONReader.readRegions($0, codes: Worldview.regionCodes) } ?? [:]

struct World {
    var built: [BuiltCountry] = []
    var rivers: [RiverBuilder.Built] = []
    var shores: [[GeoPoint]] = []
    var skipped: [String] = []
    var fallbacks = 0
}

/// Lakes cut out, outlines simplified, meshes and rivers built: one worldview's globe.
func buildWorld(_ originals: [CountryInput]) -> World {
    var world = World()
    // The globe's land, with the lakes taken out. Colors, the catalog and the city list keep
    // working from the whole countries.
    var shaped = originals
    var rawShores: [[GeoPoint]] = []
    if let lakes {
        let result = LakeCutter.cut(originals, lakes: lakes)
        shaped = result.countries
        rawShores = result.shores
        world.shores = result.shores.map { TopologySimplifier.simplifyClosed($0, tolerance: tolerance) }
        world.skipped = result.skipped
    }
    let countries = TopologySimplifier.simplify(shaped, tolerance: tolerance)
    for (country, original) in zip(countries, shaped) {
        var builder = SphereMeshBuilder(maxEdgeDegrees: 1.5, densifyStepDegrees: 0.75)
        for (polygon, originalPolygon) in zip(country.polygons, original.polygons) {
            builder.add(polygon, original: originalPolygon)
        }
        world.fallbacks += builder.fallbackCount
        world.built.append(BuiltCountry(
            code: country.code,
            colorSlot: slotByCode[country.code] ?? 0,
            label: country.label,
            rings: builder.rings,
            vertices: builder.vertices,
            indices: builder.indices
        ))
    }
    if let riverSources {
        // Lakes are matched against their unsimplified shores, as cut.
        world.rivers = RiverBuilder.build(riverSources, countries: countries, shores: rawShores, tolerance: tolerance)
    }
    return world
}

/// Disputed land, unsimplified: it decides which country a point belongs to, and cities sit
/// right at the water (Sevastopol on its bay).
func disputes(in worldview: Worldview?) -> [(code: String, rings: [[GeoPoint]])] {
    Worldview.disputes(in: worldview, countries: originals, regions: regions).map { ($0.code, $0.polygons.flatMap(\.rings)) }
}

let base = buildWorld(originals)
let data = WorldFileWriter.encode(base.built, lakes: base.shores, rivers: base.rivers, disputes: admin1Input == nil ? [] : disputes(in: nil))
try data.write(to: output)
var lakeSummary = ""
if lakes != nil {
    lakeSummary = "\nlakes: \(lakes!.count) selected, \(base.shores.count) cut into land"
    if !base.skipped.isEmpty { lakeSummary += ", left as land: \(base.skipped.joined(separator: ", "))" }
}
if riverSources != nil {
    lakeSummary += "\nrivers: \(base.rivers.count) lines, \(base.rivers.reduce(0) { $0 + $1.points.count }) points"
}

// Overlays: only what each worldview changes.
var worldviewSummary = ""
for view in admin1Input == nil ? [] : Worldview.all {
    let world = buildWorld(try view.apply(to: originals, regions: regions))
    let baseByCode = Dictionary(base.built.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
    let changed = world.built.filter { baseByCode[$0.code] != $0 }
    let changedCodes = Set(changed.map(\.code))
    let kept = Set(world.built.map(\.code))
    let removed = base.built.map(\.code).filter { !kept.contains($0) }
    let gone = changedCodes.union(removed)

    // The app keeps the base's rivers for every other country: they must come out the same.
    func others(_ world: World) -> [RiverBuilder.Built] {
        world.rivers.filter { !gone.contains(world.built[$0.country].code) }
            .map { RiverBuilder.Built(country: 0, points: $0.points, ranks: $0.ranks, weights: $0.weights) }
    }
    guard others(world) == others(base) else { throw PipelineError.malformed("worldview \(view.id) changed rivers outside \(changedCodes.sorted())") }

    let overlayIndex = Dictionary(changed.enumerated().map { ($1.code, $0) }, uniquingKeysWith: { first, _ in first })
    let rivers = world.rivers.compactMap { river -> RiverBuilder.Built? in
        overlayIndex[world.built[river.country].code].map {
            RiverBuilder.Built(country: $0, points: river.points, ranks: river.ranks, weights: river.weights)
        }
    }
    let overlay = WorldFileWriter.encode(changed, lakes: [], rivers: rivers, disputes: disputes(in: view), removed: removed, isOverlay: true)
    let url = output.deletingLastPathComponent().appending(path: output.deletingPathExtension().lastPathComponent + "-\(view.id).nmgeo")
    try overlay.write(to: url)
    worldviewSummary += "\nworldview \(view.id): \(changed.map(\.code).sorted().joined(separator: ", ")) redrawn"
        + (removed.isEmpty ? "" : ", \(removed.joined(separator: ", ")) removed")
        + ", \(rivers.count) rivers, " + ByteCountFormatter.string(fromByteCount: Int64(overlay.count), countStyle: .file)
}
let built = base.built
let fallbacks = base.fallbacks

var catalogSummary = ""
if let catalogOutput {
    // Areas come from the unsimplified outlines.
    let entries = try CountryCatalog.entries(originals)
    try CountryCatalog.encode(entries).write(to: catalogOutput)
    catalogSummary = "\ncatalog: \(entries.count) places, \(entries.filter(\.sovereign).count) countries"
}
if let placesInput, let citiesOutput {
    // Cities on disputed land go to its owner in the default worldview, like the globe.
    let owned = Worldview.disputes(in: nil, countries: originals, regions: regions)
    let cities = try CityCatalogBuilder.entries(placesInput, countries: Set(originals.map(\.code).filter { !$0.isEmpty })) { point in
        owned.first { dispute in dispute.polygons.contains { polygon in
            polygon.rings.reduce(false) { inside, ring in inside != PolygonClipper.contains(ring, point) }
        } }?.code
    }
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
file: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s\(lakeSummary)\(worldviewSummary)\(catalogSummary)
""")
