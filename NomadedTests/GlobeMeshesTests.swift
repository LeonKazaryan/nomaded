import CoreGraphics
import Foundation
import Testing
import simd
@testable import Nomaded

struct GlobeMeshesTests {
    @Test func sphereIsClosedAndInRange() {
        let mesh = GlobeMeshes.sphere(radius: 1, segments: 8, rings: 4)
        #expect(mesh.positions.count == 9 * 5)
        #expect(mesh.indices.count == 8 * 4 * 6)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
        #expect(mesh.positions.allSatisfy { abs(simd_length($0) - 1) < 1e-5 })
    }

    @Test func packRebasesIndices() {
        let a = MeshData(positions: [.zero, .one, .one], indices: [0, 1, 2])
        let b = MeshData(positions: [.one, .zero, .zero, .one], indices: [0, 2, 3, 3, 1, 0])
        let packed = GlobeMeshes.pack([a, b])

        #expect(packed.mesh.positions.count == 7)
        #expect(packed.mesh.indices == [0, 1, 2, 3, 5, 6, 6, 4, 3])
        #expect(packed.ranges == [MeshRange(indexStart: 0, indexCount: 3), MeshRange(indexStart: 3, indexCount: 6)])
    }

    @Test func wallsRunFromTopToBottom() {
        let square: [SIMD2<Float>] = [[0, 0], [1, 0], [1, 1], [0, 1]]
        let shape = CountryShape(
            code: "XX", colorSlot: 0, label: GeoCoordinate(latitude: 0.5, longitude: 0.5),
            bounds: GeoBounds(minLongitude: 0, minLatitude: 0, maxLongitude: 1, maxLatitude: 1),
            rings: [square], vertices: [], indices: []
        )
        let walls = GlobeMeshes.walls(shape, top: 1.003, bottom: 0.9)

        #expect(walls.positions.count == 8)
        // Two triangles per side, drawn both ways round.
        #expect(walls.indices.count == 4 * 12)
        #expect(abs(simd_length(walls.positions[0]) - 1.003) < 1e-5)
        #expect(abs(simd_length(walls.positions[1]) - 0.9) < 1e-5)
    }

    /// The renderer's matrix and the hit-test ray must agree, or taps would land beside the
    /// countries they're aimed at.
    @Test(arguments: [CGPoint(x: 201, y: 437), CGPoint(x: 120, y: 300), CGPoint(x: 330, y: 610)])
    func projectionMatchesTheTapRay(_ point: CGPoint) throws {
        // Also with the globe slid up over a panel, or aside of one (an iPad held sideways).
        for (distance, offset, shift) in [(1.2, 0.0, 0.0), (3.0, 0.0, 0.0), (9.0, 0.0, 0.0), (3.0, 160.0, 0.0), (3.0, 40.0, 120.0)] {
            var camera = GlobeCamera(viewportSize: CGSize(width: 402, height: 874), distance: distance)
            camera.centerOffset = offset
            camera.centerShift = shift
            let ray = camera.ray(through: point)
            guard let hit = GeoMath.intersectUnitSphere(origin: ray.origin, direction: ray.direction) else { continue }

            let clip = camera.viewProjection * SIMD4<Float>(SIMD3<Float>(hit), 1)
            let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
            let x = Double(ndc.x + 1) / 2 * 402
            let y = Double(1 - ndc.y) / 2 * 874

            #expect(abs(x - point.x) < 0.01 && abs(y - point.y) < 0.01, "distance \(distance): (\(x), \(y))")
            #expect(ndc.z > 0 && ndc.z < 1, "depth \(ndc.z) is clipped at distance \(distance)")
        }
    }
}

struct CityLabelLayoutTests {
    /// A patch of globe seen head-on, a thousandth of a radian per point: close enough to
    /// flat for the few degrees these tests span.
    private let pointsPerRadian = 1000.0
    private let screen = CGRect(x: 0, y: 0, width: 402, height: 874)

    private func label(_ name: String, _ x: CGFloat, _ y: CGFloat, highlighted: Bool = false, facing: Double = 1) -> CityLabelLayout.Candidate {
        CityLabelLayout.Candidate(
            label: CityLabel(id: UUID(), name: name, point: CGPoint(x: x, y: y), isHighlighted: highlighted),
            location: SIMD3(Double(x), Double(y), 0) / pointsPerRadian,
            facing: facing
        )
    }

    private func place(_ candidates: [CityLabelLayout.Candidate], previous: [UUID: CityLabel.Placement] = [:]) -> [CityLabel] {
        CityLabelLayout.place(candidates, in: screen, pointsPerRadian: pointsPerRadian, previous: previous)
    }

    @Test func crowdedNamesMoveAside() {
        let rome = label("Rome", 200, 400, highlighted: true)
        let tivoli = label("Tivoli", 215, 405)
        let naples = label("Naples", 260, 520)

        let placed = place([rome, tivoli, naples])
        #expect(placed.map(\.name) == ["Rome", "Tivoli", "Naples"])
        // Rome keeps the spot above; Tivoli, a moment's drive away, goes under its dot.
        #expect(placed.map(\.placement) == [.above, .below, .above])
    }

    @Test func dotsOnOneSpotShareAName() {
        let rome = label("Rome", 200, 400)
        let vatican = label("Vatican City", 196, 402)
        let placed = place([rome, vatican])
        #expect(placed.map(\.name) == ["Rome · Vatican City"])
        #expect(placed.first?.id == rome.label.id)

        let more = place([rome, vatican, label("Ostia", 203, 397, highlighted: true)])
        #expect(more.map(\.name) == ["Rome +2"])
        #expect(more.first?.isHighlighted == true)
    }

    @Test func namesNeverCoverEachOtherOrADot() {
        // A crowded region: a grid of towns 20 points apart.
        let towns = (0..<16).map { label("Town \($0)", 140 + CGFloat($0 % 4) * 20, 380 + CGFloat($0 / 4) * 20) }
        let placed = place(towns)
        let boxes = placed.map { CityLabelLayout.box(for: $0.name, at: $0.point, isCapital: $0.isCapital, placement: $0.placement) }
        #expect(placed.first?.name == "Town 0")
        #expect(placed.count < towns.count)
        for (i, box) in boxes.enumerated() {
            #expect(!boxes.dropFirst(i + 1).contains { $0.intersects(box) })
            #expect(!towns.contains { $0.label.id != placed[i].id && box.contains($0.label.point) })
        }
    }

    @Test func theHighlightedNameAlwaysShows() {
        // Rome hemmed in by Tivoli's and Ostia's dots on every side.
        let rome = label("Rome", 200, 436, highlighted: true)
        let towns = [rome, label("Vatican City", 197, 437), label("Tivoli", 216, 432), label("Ostia", 190, 448)]
        let placed = place(towns)
        #expect(placed.first?.name == "Rome · Vatican City")
        #expect(placed.first?.placement == .above)
    }

    @Test func offScreenNamesAreDropped() {
        #expect(place([label("Far", -200, 400)]).isEmpty)
    }

    /// Turning the globe squeezes dots together toward the horizon. Names still group the
    /// same way: only zooming merges or splits them.
    @Test func turningTheGlobeNeverMergesOrSplitsNames() throws {
        let camera = GlobeCamera(viewportSize: screen.size, distance: 3.7)
        let cities = [
            ("Rome", GeoCoordinate(latitude: 41.89, longitude: 12.48)),
            ("Vatican City", GeoCoordinate(latitude: 41.90, longitude: 12.45)),
            ("Siena", GeoCoordinate(latitude: 43.32, longitude: 11.33)),
        ]
        let ids = cities.map { _ in UUID() }
        func candidates(facing center: GeoCoordinate) throws -> [CityLabelLayout.Candidate] {
            let orientation = GlobeOrientation(facing: center)
            return try zip(ids, cities).map { id, city in
                let world = orientation.quaternion.act(GeoMath.unitVector(city.1))
                let point = try #require(camera.screenPoint(ofWorld: world))
                return CityLabelLayout.Candidate(
                    label: CityLabel(id: id, name: city.0, point: point, isHighlighted: false),
                    location: GeoMath.unitVector(city.1),
                    facing: camera.facing(worldPoint: world)
                )
            }
        }
        func names(_ candidates: [CityLabelLayout.Candidate]) -> Set<String> {
            Set(CityLabelLayout.place(candidates, in: screen, pointsPerRadian: camera.pointsPerRadian).map(\.name))
        }

        let headOn = try candidates(facing: cities[0].1)
        // Italy turned up toward the top of the globe.
        let turned = try candidates(facing: GeoCoordinate(latitude: -6, longitude: 12.48))
        // Up there Siena's dot sits as close to Rome's as Vatican City's did head-on…
        let squeezed = hypot(turned[0].label.point.x - turned[2].label.point.x, turned[0].label.point.y - turned[2].label.point.y)
        #expect(squeezed < CityLabelLayout.mergeDistance)
        #expect(turned.allSatisfy { $0.facing > GlobeTuning.cityLabelHorizon.upperBound })
        // …yet the names don't change.
        #expect(names(headOn) == ["Rome · Vatican City", "Siena"])
        #expect(names(turned) == names(headOn))
    }

    @Test func aShowingNameKeepsItsSide() {
        let rome = label("Rome", 200, 400)
        #expect(place([rome]).first?.placement == .above)
        // Moved under its dot once, it stays there while there's room.
        #expect(place([rome], previous: [rome.label.id: .below]).first?.placement == .below)
    }

    /// A name squeezed a point away from another stays, but a new one needs room to spare,
    /// so neither blinks as the globe turns a little back and forth.
    @Test func aNewNameNeedsRoomToSpare() {
        let rome = label("Rome", 200, 400)
        // Pisa's spot above its dot ends a point after Rome's begins.
        let pisa = label("Pisa", 253, 400)
        let fresh = place([rome, pisa])
        #expect(fresh.map(\.placement) == [.above, .below])
        let kept = place([rome, pisa], previous: [rome.label.id: .above, pisa.label.id: .above])
        #expect(kept.map(\.placement) == [.above, .above])
    }

    @Test func namesSinkBeforeTheHorizon() {
        let low = label("Hammerfest", 200, 40, facing: 0.25)
        #expect(place([low]).isEmpty)
        // One already showing lasts a little longer…
        #expect(place([low], previous: [low.label.id: .below]).count == 1)
        // …but not to the horizon itself.
        let lower = label("Vardø", 200, 30, facing: 0.1)
        #expect(place([lower], previous: [lower.label.id: .below]).isEmpty)
    }

    @Test func aNameSinksBeforeItChanges() {
        let above = CityLabel(id: UUID(), name: "Rome", point: CGPoint(x: 200, y: 400), isHighlighted: false)
        var motion = CityLabelMotion(above)
        for _ in 0..<60 { motion.step(1.0 / 60, toward: above, reduceMotion: false) }
        #expect(motion.appearance.value > 0.9)

        var below = above
        below.placement = .below
        // Still on its old side, on its way into the dot…
        motion.step(1.0 / 60, toward: below, reduceMotion: false)
        #expect(motion.placement == .above)
        #expect(motion.appearance.target == 0)
        // …then out again under it.
        for _ in 0..<60 { motion.step(1.0 / 60, toward: below, reduceMotion: false) }
        #expect(motion.placement == .below)
        #expect(motion.appearance.value > 0.9)

        // With Reduce Motion it just switches.
        motion.step(1.0 / 60, toward: above, reduceMotion: true)
        #expect(motion.placement == .above)
        #expect(motion.appearance.value == 1)
    }

    @Test func screenPointInvertsTheTapRay() throws {
        let camera = GlobeCamera(viewportSize: CGSize(width: 402, height: 874), distance: 2.5)
        let tap = CGPoint(x: 150, y: 380)
        let ray = camera.ray(through: tap)
        let hit = try #require(GeoMath.intersectUnitSphere(origin: ray.origin, direction: ray.direction))
        let back = try #require(camera.screenPoint(ofWorld: hit))

        #expect(abs(back.x - tap.x) < 1e-6 && abs(back.y - tap.y) < 1e-6)
        #expect(camera.faces(worldPoint: hit))
        #expect(!camera.faces(worldPoint: -hit))
        #expect(abs(camera.facing(worldPoint: [0, 0, 1]) - 1) < 1e-9)
    }
}
