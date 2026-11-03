import CoreGraphics
import Foundation
import SwiftUI

/// Outlines for the continent mini-maps on the statistics screen, projected once off the
/// main thread. Each continent is seen the way the globe shows it (orthographic), so
/// Oceania across the date line and Antarctica around the pole come out right.
struct ContinentMaps: Sendable {
    struct Outline: Sendable {
        let code: String
        let colorSlot: Int
        /// On this continent. Neighbours from other continents are drawn faint, for context.
        let isHome: Bool
        /// Unit coordinates: 1 is the frame's radius, y points down. Even-odd fill.
        let path: Path
        /// Where the country pops from: its label point.
        let center: CGPoint
        /// Too small to see as a shape (Malta, Singapore); drawn as a dot once visited.
        let isTiny: Bool
    }

    /// What a tile shows: everything within `radius` degrees of `center` fits the tile's
    /// shorter side.
    struct Frame: Sendable {
        let center: GeoCoordinate
        let radius: Double
    }

    static let frames: [Continent: Frame] = [
        .europe: Frame(center: GeoCoordinate(latitude: 54, longitude: 15), radius: 19),
        .asia: Frame(center: GeoCoordinate(latitude: 38, longitude: 92), radius: 36),
        .africa: Frame(center: GeoCoordinate(latitude: 2, longitude: 18), radius: 37),
        .northAmerica: Frame(center: GeoCoordinate(latitude: 45, longitude: -100), radius: 33),
        .southAmerica: Frame(center: GeoCoordinate(latitude: -22, longitude: -60), radius: 35),
        .oceania: Frame(center: GeoCoordinate(latitude: -26, longitude: 150), radius: 26),
        .antarctica: Frame(center: GeoCoordinate(latitude: -90, longitude: 0), radius: 29),
    ]

    let outlines: [Continent: [Outline]]

    nonisolated static func build(world: WorldGeometry, catalog: CountryCatalog) async -> ContinentMaps {
        var outlines: [Continent: [Outline]] = [:]
        for (continent, frame) in frames {
            let projection = Projection(frame)
            outlines[continent] = world.countries.compactMap { shape in
                outline(shape, home: catalog[shape.code]?.continent == continent, projection)
            }
        }
        return ContinentMaps(outlines: outlines)
    }

    private static func outline(_ shape: CountryShape, home: Bool, _ projection: Projection) -> Outline? {
        // Anything past this is off every tile, whatever its shape.
        let reach: CGFloat = 2.2
        var path = Path()
        var bounds = CGRect.null
        for ring in shape.rings {
            var points: [CGPoint] = []
            points.reserveCapacity(ring.count)
            for vertex in ring {
                let point = projection.point(longitude: Double(vertex.x), latitude: Double(vertex.y))
                // Half a point on a tile: closer vertices add nothing visible.
                if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 0.008 { continue }
                points.append(point)
            }
            guard points.count >= 3 else { continue }
            let ringBounds = Path { $0.addLines(points) }.boundingRect
            guard abs(ringBounds.midX) - ringBounds.width / 2 < reach,
                  abs(ringBounds.midY) - ringBounds.height / 2 < reach
            else { continue }
            path.addLines(points)
            path.closeSubpath()
            bounds = bounds.union(ringBounds)
        }

        let center = projection.point(longitude: shape.label.longitude, latitude: shape.label.latitude)
        let isTiny = bounds.isNull || max(bounds.width, bounds.height) < 0.03
        // Tiny places only matter on their own continent, and only if they're in view.
        if isTiny, !home || abs(center.x) > reach || abs(center.y) > reach || !projection.faces(shape.label) {
            return nil
        }
        return Outline(code: shape.code, colorSlot: shape.colorSlot, isHome: home, path: path, center: center, isTiny: isTiny)
    }

    /// Orthographic projection around a frame's center, scaled so its radius is 1.
    struct Projection: Sendable {
        let center: GeoCoordinate
        let scale: Double

        init(_ frame: Frame) {
            center = frame.center
            scale = 1 / sin(GeoMath.radians(frame.radius))
        }

        func faces(_ coordinate: GeoCoordinate) -> Bool {
            GeoMath.angularDistance(center, coordinate) < .pi / 2
        }

        func point(longitude: Double, latitude: Double) -> CGPoint {
            let phi = GeoMath.radians(latitude), phi0 = GeoMath.radians(center.latitude)
            let dLambda = GeoMath.radians(longitude - center.longitude)
            var x = cos(phi) * sin(dLambda)
            var y = cos(phi0) * sin(phi) - sin(phi0) * cos(phi) * cos(dLambda)
            // The far side folds onto the horizon, which is well off every tile.
            if sin(phi0) * sin(phi) + cos(phi0) * cos(phi) * cos(dLambda) < 0 {
                let length = max(hypot(x, y), 1e-9)
                x /= length
                y /= length
            }
            return CGPoint(x: x * scale, y: -y * scale)
        }
    }
}
