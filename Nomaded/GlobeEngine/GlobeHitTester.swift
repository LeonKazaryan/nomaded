/// Finds the country under a point on the globe.
struct GlobeHitTester: Sendable {
    /// Countries smaller than this (in degrees) also count as hit when a tap lands near them.
    static let microStateSpan: Float = 1

    private let shapes: [CountryShape]
    private let microStates: [CountryShape]

    init(world: WorldGeometry) {
        shapes = world.countries.filter { !$0.code.isEmpty }
        microStates = shapes.filter { $0.bounds.span < Self.microStateSpan }
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

        let nearest = microStates
            .map { (code: $0.code, distance: GeoMath.angularDistance(coordinate, $0.label)) }
            .min { $0.distance < $1.distance }
        guard let nearest, nearest.distance <= tolerance else { return nil }
        return nearest.code
    }
}
