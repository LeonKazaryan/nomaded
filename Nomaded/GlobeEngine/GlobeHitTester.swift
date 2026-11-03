import simd

/// Finds the country under a point on the globe.
struct GlobeHitTester: Sendable {
    /// Countries smaller than this (in degrees) also count as hit when a tap lands near them.
    static let microStateSpan: Float = 1

    private let shapes: [CountryShape]
    private let microStates: [CountryShape]
    private let lakes: [LakeShape]

    init(world: WorldGeometry) {
        shapes = world.countries.filter { !$0.code.isEmpty }
        microStates = shapes.filter { $0.bounds.span < Self.microStateSpan }
        lakes = world.lakes
    }

    /// - Parameter tolerance: Angular radius (radians) around a micro-state's center that
    ///   still selects it. Monaco is far smaller than a fingertip.
    func country(at coordinate: GeoCoordinate, tolerance: Double) -> String? {
        let longitude = Float(coordinate.longitude)
        let latitude = Float(coordinate.latitude)
        let direct = shapes.first {
            $0.bounds.contains(longitude: longitude, latitude: latitude)
                && GeoMath.ringsContain($0.rings, longitude: longitude, latitude: latitude)
        }
        if let direct { return direct.code }

        // A lake counts as the land around it: Baikal is Russia, and a tap on Lake Victoria
        // picks the country whose shore is nearest. Finland would be hard to hit otherwise.
        if let lake = lakes.first(where: {
            $0.bounds.contains(longitude: longitude, latitude: latitude)
                && GeoMath.ringsContain([$0.shore], longitude: longitude, latitude: latitude)
        }) {
            return country(nearest: SIMD2(longitude, latitude), around: lake)
        }

        let nearest = microStates
            .map { (code: $0.code, distance: GeoMath.angularDistance(coordinate, $0.label)) }
            .min { $0.distance < $1.distance }
        guard let nearest, nearest.distance <= tolerance else { return nil }
        return nearest.code
    }

    /// The country with the shore closest to a point in a lake. Distances are measured on a
    /// plane squeezed east–west like the ground at that latitude.
    private func country(nearest point: SIMD2<Float>, around lake: LakeShape) -> String? {
        // The countries' shores are simplified separately from the lake's: a little slack.
        let slack: Float = 0.2
        let area = GeoBounds(
            minLongitude: lake.bounds.minLongitude - slack, minLatitude: lake.bounds.minLatitude - slack,
            maxLongitude: lake.bounds.maxLongitude + slack, maxLatitude: lake.bounds.maxLatitude + slack
        )
        let squeeze = SIMD2<Float>(cos(point.y * .pi / 180), 1)
        var best: (code: String, distance: Float)?
        for shape in shapes where shape.bounds.overlaps(area) {
            for ring in shape.rings {
                var previous = ring[ring.count - 1]
                for vertex in ring {
                    defer { previous = vertex }
                    guard area.contains(longitude: vertex.x, latitude: vertex.y) else { continue }
                    let distance = Self.distance(from: point * squeeze, previous * squeeze, vertex * squeeze)
                    if distance < best?.distance ?? .infinity { best = (shape.code, distance) }
                }
            }
        }
        return best?.code
    }

    private static func distance(from p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let lengthSquared = simd_length_squared(ab)
        guard lengthSquared > 0 else { return simd_distance(p, a) }
        let t = max(0, min(1, simd_dot(p - a, ab) / lengthSquared))
        return simd_distance(p, a + ab * t)
    }
}
