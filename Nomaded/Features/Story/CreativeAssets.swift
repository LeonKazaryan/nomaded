#if DEBUG
import CoreImage
import ImageIO
import Metal
import SwiftUI
import UniformTypeIdentifiers
import os

/// The App Store's creative assets for iOS 27 (docs/09-store-listing.md → «Креативные
/// материалы»), drawn by the app's own globe offscreen, the way a story is (`StoryFilm`):
/// the product page header (a 21:9 video that loops, and its first frame as a picture) and
/// the search results picture, 3:2, in the app's language.
/// `-NomadedDebugCreative YES` shows this instead of the globe screen
/// (`-NomadedDebugCreativeHeader YES`: the header too); the files land in `tmp/Creative/`,
/// and `Tools/Screenshots/creative.sh` collects them. Debug only.
struct CreativeStudio: View {
    @State private var status = "Drawing the App Store assets…"

    var body: some View {
        ZStack {
            SpaceBackground()
            Text(verbatim: status)
                .font(Typography.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(32)
        }
        .task {
            status = await CreativeAssets.renderAll { status = $0 }
        }
    }
}

@MainActor
enum CreativeAssets {
    static let folder = URL.temporaryDirectory.appending(path: "Creative", directoryHint: .isDirectory)
    fileprivate static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    fileprivate static let log = Logger(subsystem: "com.leonkazaryan.nomaded", category: "Creative")

    /// The traveller of the App Store screenshots (`Tools/Screenshots/capture.sh`), with
    /// Japan: 35 countries on six continents. Nothing on disputed land is lit.
    fileprivate static let traveller: Set<String> = [
        "IT", "FR", "ES", "PT", "DE", "NL", "CH", "AT", "CZ", "GR", "HR", "GB", "IE", "NO", "IS",
        "TH", "VN", "ID", "TR", "AE", "GE", "KZ", "KR", "JP", "US", "CA", "MX", "BR", "AR", "PE",
        "MA", "EG", "ZA", "AU", "NZ",
    ]

    /// Everything for the app's current language, then `done.txt`, which the script waits
    /// for. Returns what to show on screen.
    static func renderAll(progress: (String) -> Void) async -> String {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let started = CACurrentMediaTime()
        var report: String
        do {
            let world = try await WorldGeometry.loadBundled(.standard)
            progress("Search results picture (\(language))…")
            try await SearchPicture.render(world: world, language: language, to: folder.appending(path: "search-\(language).png"))
            if UserDefaults.standard.bool(forKey: "NomadedDebugCreativeHeader") {
                try await HeaderLoop.render(
                    world: world,
                    video: folder.appending(path: "header.mp4"),
                    still: folder.appending(path: "header.png")
                ) { progress("Header video… \(Int($0 * 100))%") }
            }
            report = "Done in \(Int(CACurrentMediaTime() - started)) s"
        } catch {
            report = "Failed: \(error)"
            log.error("Creative assets failed: \(error)")
        }
        try? report.write(to: folder.appending(path: "done.txt"), atomically: true, encoding: .utf8)
        return report
    }
}

// MARK: - Header

/// The product page header: deep space, and the globe turning the way the Earth does, the
/// traveller's countries lighting up one by one as they come round, each with its flag
/// popping up on it, now and then a ring running off across the planet. 20 s, and it loops
/// with no seam: a country fills before the middle and drains round the back, where nobody
/// sees, so the last frame leads into the first.
@MainActor
private enum HeaderLoop {
    /// Points, drawn at 2×: 3840×1646, 21:9.
    static let size = CGSize(width: 1920, height: 823)
    static let scale = 2.0
    static let framesPerSecond = 30
    /// One turn of the globe, and the length of the loop.
    static let period = 20.0
    /// Whole and in the middle, where a header cropped to a narrower screen still has it.
    static let radius = 318.0
    static let latitude = 18.0
    /// Where the first frame faces, which is also the picture: Europe and Africa lit.
    static let opening = 10.0
    /// A country fills this many degrees before the middle, as it comes round from the left.
    static let fillBefore = 22.0
    /// A drain needs this much of the turn (about 1.5 s) out of sight to finish unseen.
    static let drainSpan = 30.0
    /// These throw a ring across the planet as they fill; one at a time, spread round it.
    static let ringers: Set<String> = ["JP", "BR", "EG", "AU", "KZ"]

    static let cities: [GlobeController.CityMarker] = [
        ("Paris", "FR", 48.86, 2.35, true), ("Rome", "IT", 41.9, 12.5, true), ("Barcelona", "ES", 41.39, 2.17, false),
        ("Lisbon", "PT", 38.72, -9.14, true), ("Istanbul", "TR", 41.01, 28.98, false), ("Dubai", "AE", 25.2, 55.27, false),
        ("Bangkok", "TH", 13.75, 100.5, true), ("Tokyo", "JP", 35.68, 139.69, true), ("Kyoto", "JP", 35.01, 135.77, false),
        ("Seoul", "KR", 37.57, 126.98, true), ("Almaty", "KZ", 43.24, 76.89, false), ("New York", "US", 40.71, -74.0, false),
        ("Mexico City", "MX", 19.43, -99.13, true), ("Rio de Janeiro", "BR", -22.91, -43.17, false),
        ("Buenos Aires", "AR", -34.6, -58.38, true), ("Cape Town", "ZA", -33.92, 18.42, false), ("Marrakesh", "MA", 31.63, -7.99, false),
        ("Cairo", "EG", 30.04, 31.24, true), ("Sydney", "AU", -33.87, 151.21, false), ("Bali", "ID", -8.65, 115.22, false),
    ].map { name, code, latitude, longitude, isCapital in
        GlobeController.CityMarker(
            id: UUID(), name: name, countryCode: code,
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude), isCapital: isCapital
        )
    }

    /// When a country fills and drains, as the longitude the globe faces (wrapped).
    struct Cycle {
        let code: String
        let label: GeoCoordinate
        let fillAt: Double
        let drainAt: Double
    }

    static func render(world: WorldGeometry, video: URL, still: URL, progress: (Double) -> Void) async throws {
        let stage = try await OffscreenGlobe(world: world, size: size, scale: scale)
        let globe = stage.globe
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let pixels = (width: Int(size.width * scale), height: Int(size.height * scale))

        // A country that never quite leaves the view (Alaska, Canada's north: the north
        // pole shows the whole time) stays lit; the rest come and go.
        let shapes = Dictionary(world.countries.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        var cycles: [Cycle] = []
        var steady: Set<String> = []
        for code in CreativeAssets.traveller {
            guard let shape = shapes[code] else { continue }
            if let drainAt = drainLongitude(of: shape) {
                cycles.append(Cycle(code: code, label: shape.label, fillAt: wrap(shape.label.longitude + fillBefore), drainAt: drainAt))
            } else {
                steady.insert(code)
            }
        }
        CreativeAssets.log.notice("Header: \(cycles.count) countries come and go, \(steady.sorted()) stay lit")

        globe.setCities(cities)
        var lit = steady
        globe.setVisited(lit)
        let zoom = stage.zoom(radius: radius)
        let perFrame = 1.0 / Double(framesPerSecond)
        let turnFrames = Int(period * Double(framesPerSecond))
        // A whole turn and a second first, unrecorded: from then on each frame is the frame a
        // turn later, every fill, drain, ring and flag included, so the loop has no seam.
        let warmUp = turnFrames + framesPerSecond
        let facing = { (frame: Int) in opening - 360 * Double(frame - warmUp) / Double(turnFrames) }
        globe.renderStill(facing: GeoCoordinate(latitude: latitude, longitude: facing(0)), zoom: zoom, offset: 0, into: stage.texture)

        let backdrop = stage.layer(SpaceStill(time: 0), opaque: true)
        let shading = stage.layer(GlobeShading(radius: radius, center: center))
        var pins = Pins(scale: scale, canvasHeight: size.height)
        let writer = try VideoWriter(url: video, width: pixels.width, height: pixels.height, framesPerSecond: framesPerSecond, bitRate: 40_000_000)
        var previous: Double?
        do {
            for frame in 0..<(warmUp + turnFrames) {
                let time = Double(frame) * perFrame
                globe.aim(at: GeoCoordinate(latitude: latitude, longitude: facing(frame)))
                let now = globe.facingLongitude
                if let previous {
                    for cycle in cycles {
                        if passed(cycle.fillAt, from: previous, to: now) {
                            lit.insert(cycle.code)
                            globe.setVisited(lit)
                            globe.celebrate(cycle.code, quietly: !ringers.contains(cycle.code))
                            pins.pop(cycle.code, at: cycle.label, time: time, on: globe)
                        } else if passed(cycle.drainAt, from: previous, to: now) {
                            lit.remove(cycle.code)
                            globe.setVisited(lit)
                            globe.drain(cycle.code)
                        }
                    }
                }
                previous = now
                globe.renderFilmFrame(deltaTime: perFrame, into: stage.texture)
                pins.forget(behind: now)
                guard frame >= warmUp else {
                    if frame % 15 == 0 { await Task.yield() }
                    continue
                }
                let image = stage.frame(backdrop: backdrop, layers: [shading, pins.layer(at: time, on: globe)].compactMap { $0 })
                if frame == warmUp { try stage.writePNG(image, to: still) }
                try await writer.append(image, context: stage.context, colorSpace: CreativeAssets.sRGB)
                progress(Double(frame - warmUp + 1) / Double(turnFrames))
                await Task.yield()
            }
            try await writer.finish()
        } catch {
            writer.cancel()
            throw error
        }
    }

    /// The facing longitude, as the globe turns, at which the whole country has been out of
    /// sight long enough for its color to drain unseen: the start of its longest stretch
    /// behind the globe, if that stretch is at least `drainSpan`. `nil` if it never hides.
    static func drainLongitude(of shape: CountryShape) -> Double? {
        let tilt = latitude * .pi / 180
        let points = shape.rings.joined().enumerated().compactMap { $0.offset % 3 == 0 ? $0.element : nil }
            .map { (latitude: Double($0.y) * .pi / 180, longitude: Double($0.x)) }
        // Hidden: every point faces away (a margin for the lift and the outline's detail).
        let hidden = (0..<360).map { facing in
            points.allSatisfy { point in
                cos(tilt) * cos(point.latitude) * cos((point.longitude - Double(facing)) * .pi / 180)
                    + sin(tilt) * sin(point.latitude) < -0.04
            }
        }
        guard hidden.contains(false) else { return nil }
        // Runs of hidden longitudes round the circle, starting just after a visible one.
        let first = hidden.firstIndex(of: false)!
        var best: (top: Int, length: Int)?
        var length = 0
        for step in 1...360 {
            let facing = (first + step) % 360
            if hidden[facing] {
                length += 1
            } else {
                if length > 0, length > (best?.length ?? 0) { best = (facing - 1, length) }
                length = 0
            }
        }
        guard let best, Double(best.length) >= drainSpan else { return nil }
        // The globe turns west, the facing longitude falling: a stretch is entered at its top.
        return wrap(Double(best.top) - 1)
    }

    /// Whether the falling facing longitude went past `mark` between two frames.
    static func passed(_ mark: Double, from previous: Double, to now: Double) -> Bool {
        let before = wrap(previous - mark), after = wrap(now - mark)
        return before > 0 && after <= 0 && before - after < 90
    }

    /// Into -180…180.
    static func wrap(_ degrees: Double) -> Double {
        let turned = (degrees + 180).truncatingRemainder(dividingBy: 360)
        return (turned < 0 ? turned + 360 : turned) - 180
    }

    /// A flag on each country as it fills, riding round with it, gone over the horizon.
    /// Same as a story's, bigger.
    struct Pins {
        private struct Pin {
            let code: String
            let place: GeoCoordinate
            let born: Double
        }

        /// Flags as big as this many of a story's.
        private static let size = 1.7
        /// A new flag closer than this (points) to one already up stays down.
        private static let spacing = 46.0

        private let scale: Double
        private let canvasHeight: Double
        private var pins: [Pin] = []
        private var images: [String: CIImage] = [:]

        init(scale: Double, canvasHeight: Double) {
            self.scale = scale
            self.canvasHeight = canvasHeight
        }

        mutating func pop(_ code: String, at place: GeoCoordinate, time: Double, on globe: GlobeController) {
            guard let new = globe.screenPoint(of: place) else { return }
            let crowded = pins.contains { pin in
                guard let point = globe.screenPoint(of: pin.place)?.point else { return false }
                return hypot(point.x - new.point.x, point.y - new.point.y) < Self.spacing
            }
            guard !crowded else { return }
            if images[code] == nil {
                let renderer = ImageRenderer(content: StoryPin(flag: RegionDisplay.flag(for: code)))
                renderer.scale = scale * Self.size
                images[code] = renderer.cgImage.map { CIImage(cgImage: $0) }
            }
            pins.append(Pin(code: code, place: place, born: time))
        }

        /// Flags whose country has gone round the back.
        mutating func forget(behind facing: Double) {
            pins.removeAll { HeaderLoop.wrap($0.place.longitude - facing) > 110 }
        }

        func layer(at time: Double, on globe: GlobeController) -> CIImage? {
            let pixelsPerPoint = scale * Self.size
            let tip = CGPoint(x: StoryPin.tip.x * pixelsPerPoint, y: (StoryPin.size.height - StoryPin.tip.y) * pixelsPerPoint)
            var layer: CIImage?
            for pin in pins {
                guard let image = images[pin.code], let spot = globe.screenPoint(of: pin.place) else { continue }
                let age = time - pin.born
                let opacity = min(1, age / 0.08) * OffscreenGlobe.smoothstep((spot.facing - 0.12) / 0.25)
                guard opacity > 0.005 else { continue }
                let grow = max(0.01, StoryPin.scale(age: age))
                let target = CGPoint(x: spot.point.x * scale, y: (canvasHeight - spot.point.y) * scale)
                let placed = OffscreenGlobe.faded(image.transformed(by: CGAffineTransform(translationX: -tip.x, y: -tip.y)
                    .concatenating(CGAffineTransform(scaleX: grow, y: grow))
                    .concatenating(CGAffineTransform(translationX: target.x, y: target.y))), by: opacity)
                layer = layer.map(placed.composited(over:)) ?? placed
            }
            return layer
        }
    }
}

// MARK: - Search results

/// The search results picture: what the app is about in one glance, for someone scrolling
/// past. On the left a short line and the traveller's numbers; on the right the globe, big,
/// Europe in color, Italy just marked: the fill halfway across, the ring running off,
/// confetti in the air, the passport stamp pressed beside it.
@MainActor
private enum SearchPicture {
    /// Points, drawn at 2×: 3840×2560, 3:2.
    static let size = CGSize(width: 1920, height: 1280)
    static let scale = 2.0
    /// The globe's square, its left edge, and the globe in it, running a little off the right.
    static let globeSide = 1280.0
    static let globeLeft = 770.0
    static let radius = 610.0
    static let facing = GeoCoordinate(latitude: 34, longitude: 22)
    static let marked = "IT"
    /// How far into Italy's celebration the picture is, in seconds.
    static let moment = 0.62
    static let stampDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 7, day: 12).date!

    static func render(world: WorldGeometry, language: String, to url: URL) async throws {
        let square = CGSize(width: globeSide, height: globeSide)
        let stage = try await OffscreenGlobe(world: world, size: square, scale: scale)
        let globe = stage.globe
        globe.setVisited(CreativeAssets.traveller.subtracting([marked]))
        globe.renderStill(facing: facing, zoom: stage.zoom(radius: radius), offset: 0, into: stage.texture)
        // Marked now: everything else is at rest, Italy is in the middle of its moment.
        globe.aim(at: facing)
        globe.setVisited(CreativeAssets.traveller)
        let origin = globe.celebrate(marked) ?? CGPoint(x: globeSide / 2, y: globeSide / 2)
        let step = 1.0 / 120
        for _ in 0..<Int(moment / step) {
            globe.aim(at: facing)
            globe.renderFilmFrame(deltaTime: step, into: stage.texture)
        }

        let ink = globe.visitedColor(of: marked).map(Color.init(components:)) ?? Palette.accentLight
        let center = CGPoint(x: globeLeft + globeSide / 2, y: globeSide / 2)
        let burst = CGPoint(x: globeLeft + origin.x, y: origin.y)
        let stats = StatsCalculator.stats(visited: CreativeAssets.traveller, catalog: .bundled)
        let canvas = OffscreenCanvas(size: size, scale: scale, context: stage.context)
        let planet = stage.planet.transformed(by: CGAffineTransform(translationX: globeLeft * scale, y: (size.height - globeSide) * scale))
        let image = canvas.frame(backdrop: canvas.layer(SpaceStill(time: 0), opaque: true), layers: [
            planet,
            canvas.layer(GlobeShading(radius: radius, center: center)),
            canvas.layer(SearchConfetti(origin: burst, ink: ink, time: moment - 0.05)),
            canvas.layer(SearchWords(language: language, stats: stats, stamp: StampSpot(code: marked, ink: ink, date: stampDate, near: burst))),
        ])
        try canvas.writePNG(image, to: url)
    }
}

/// Where the passport stamp goes: above Italy, toward the words.
private struct StampSpot {
    let code: String
    let ink: Color
    let date: Date
    let near: CGPoint
}

/// The line, the numbers and the stamp, over the whole picture.
private struct SearchWords: View {
    let language: String
    let stats: WorldStats
    let stamp: StampSpot

    /// The line, short, in the app's two languages: it says what the picture shows you do.
    private var line: String {
        language == "ru" ? "Зажги каждую страну, где ты был" : "Light up every country you've been to"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 44) {
                Text(verbatim: line)
                    .font(.system(size: 104, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                counter
            }
            .frame(width: 700, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.leading, 120)

            PassportStamp(code: stamp.code, date: stamp.date, ink: stamp.ink, slamsIn: false)
                .scaleEffect(3.4)
                .rotationEffect(.degrees(4))
                .position(x: stamp.near.x - 300, y: stamp.near.y - 250)
        }
        .frame(width: SearchPicture.size.width, height: SearchPicture.size.height)
        .environment(\.colorScheme, .dark)
    }

    /// "35 countries" with the number huge, as in a story, and the share of the world under it.
    private var counter: some View {
        let count = stats.countries.visited
        let digits = count.formatted()
        var phrase = AttributedString(localized: "\(count) countries")
        phrase.font = .system(size: 58, weight: .bold, design: .rounded)
        if let range = phrase.range(of: digits) {
            phrase[range].font = .system(size: 170, weight: .heavy, design: .rounded)
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(phrase)
                .foregroundStyle(LinearGradient(colors: [.white, Palette.accentLight], startPoint: .top, endPoint: .bottom))
            HStack(spacing: 14) {
                Text("\(stats.countries.share.formatted(.percent.precision(.fractionLength(0)))) of the world")
                Text(verbatim: "·")
                Text("\(stats.visitedContinents) of \(stats.continents.count) continents")
            }
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
        }
    }
}

/// Italy's confetti, `time` seconds after it went off, thrown big enough for a picture
/// this size. The same pieces every time it's drawn.
private struct SearchConfetti: View {
    let origin: CGPoint
    let ink: Color
    let time: Double

    var body: some View {
        Canvas { context, _ in
            let pale = ink.mix(with: .white, by: 0.5)
            let burst = ConfettiBurst(origin: .zero, colors: [ink, ink, pale, .white, Palette.capital], seed: 20_260_712)
            var big = context
            big.translateBy(x: origin.x, y: origin.y)
            big.scaleBy(x: 2.6, y: 2.6)
            ConfettiView(bursts: []).draw(burst, at: time, in: big)
        }
        .frame(width: SearchPicture.size.width, height: SearchPicture.size.height)
    }
}

// MARK: - Drawing

/// A picture assembled from layers, `scale` pixels to the point, top-down points as in SwiftUI.
@MainActor
private struct OffscreenCanvas {
    let size: CGSize
    let scale: Double
    let context: CIContext

    /// A SwiftUI layer covering the whole canvas.
    func layer(_ view: some View, opaque: Bool = false) -> CIImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.isOpaque = opaque
        return renderer.cgImage.map { CIImage(cgImage: $0) } ?? CIImage.empty()
    }

    func frame(backdrop: CIImage, layers: [CIImage]) -> CIImage {
        layers.reduce(backdrop) { $1.composited(over: $0) }
            .cropped(to: CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
    }

    /// A PNG with no alpha channel: App Store Connect turns down pictures that have one.
    func writePNG(_ image: CIImage, to url: URL) throws {
        let sRGB = CreativeAssets.sRGB
        guard let drawn = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB),
              let opaque = CGContext(
                  data: nil, width: drawn.width, height: drawn.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw StoryFilmError.noGlobe }
        opaque.draw(drawn, in: CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height))
        guard let flat = opaque.makeImage(),
              let file = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw StoryFilmError.noGlobe }
        CGImageDestinationAddImage(file, flat, nil)
        guard CGImageDestinationFinalize(file) else { throw StoryFilmError.noGlobe }
    }
}

/// A globe of its own, drawn into a texture `scale` pixels to the point.
@MainActor
private struct OffscreenGlobe {
    let globe: GlobeController
    let texture: MTLTexture
    let context: CIContext
    let size: CGSize
    let scale: Double

    init(world: WorldGeometry, size: CGSize, scale: Double) async throws {
        globe = GlobeController(style: .nomaded)
        globe.setViewportSize(size)
        await globe.load(world, worldview: .standard)
        guard globe.isReady, let device = globe.device else { throw StoryFilmError.noGlobe }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: GlobeRenderer.pixelFormat, width: Int(size.width * scale), height: Int(size.height * scale), mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw StoryFilmError.noGlobe }
        self.texture = texture
        // Blending in sRGB, as on screen (see `StoryFilm`).
        context = CIContext(mtlDevice: device, options: [.workingColorSpace: CreativeAssets.sRGB])
        self.size = size
        self.scale = scale
    }

    /// The zoom at which the whole globe is `radius` points across its middle.
    func zoom(radius: Double) -> Double {
        radius / (GlobeTuning.baseDiameter(in: size) / 2)
    }

    /// The globe as last drawn. Metal's rows run top down, Core Image's bottom up.
    var planet: CIImage {
        CIImage(mtlTexture: texture, options: [.colorSpace: CreativeAssets.sRGB])?.oriented(.downMirrored) ?? CIImage.empty()
    }

    private var canvas: OffscreenCanvas { OffscreenCanvas(size: size, scale: scale, context: context) }

    func layer(_ view: some View, opaque: Bool = false) -> CIImage { canvas.layer(view, opaque: opaque) }

    /// The globe over `backdrop`, under `layers` (bottom first).
    func frame(backdrop: CIImage, layers: [CIImage]) -> CIImage {
        canvas.frame(backdrop: backdrop, layers: [planet] + layers)
    }

    func writePNG(_ image: CIImage, to url: URL) throws { try canvas.writePNG(image, to: url) }

    static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func faded(_ image: CIImage, by opacity: Double) -> CIImage {
        guard opacity < 0.995 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
    }
}
#endif
