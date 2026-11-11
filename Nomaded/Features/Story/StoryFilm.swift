import AVFoundation
import CoreImage
import Metal
import SwiftUI
import UIKit
import os

/// What a story shows: the places on the globe and their numbers.
struct StoryContent {
    /// Every visited place the globe can show, with its middle.
    let places: [StoryPlan.Place]
    /// Of those, the ones the counter counts: the 195 countries, not territories.
    let countries: Set<String>
    let stats: WorldStats
    let cities: [GlobeController.CityMarker]
    /// The screen's outlines and borders, borrowed: the story needn't load them again.
    let world: WorldGeometry
    let worldview: Worldview
}

/// A story's picture: the file to share and the image to show.
struct StoryPicture {
    let file: URL
    let image: CGImage
}

enum StoryFilmError: Error {
    case noGlobe
    case noVideo
}

/// Makes the user's world into a story (ADR-019), on a globe of its own drawn offscreen,
/// under the numbers and over deep space, 1080×1920. The picture is a single frame, ready
/// at once. The film plays `StoryPlan` frame by frame (out of hyperspace, a tour of the places
/// stop by stop, each filling with its flag, back out to the whole planet) into a video at
/// 30 fps: as fast as the phone draws, not in real time, and only when asked for.
@MainActor
enum StoryFilm {
    /// A frame in points. Drawn at 3×: 1080×1920, the size stories are made for.
    static let size = CGSize(width: 360, height: 640)
    static let scale = 3.0
    private static let pixels = (width: 1080, height: 1920)
    private static let folder = URL.temporaryDirectory.appending(path: "Story", directoryHint: .isDirectory)
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static let log = Logger(subsystem: "com.leonkazaryan.nomaded", category: "Story")

    /// The picture: everything filled and every number in, the globe turned to where most
    /// of the places are, so it shows as much color as it can. Starts a fresh story: the
    /// last one's files go.
    static func picture(_ content: StoryContent) async throws -> StoryPicture {
        let started = CACurrentMediaTime()
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stage = try await Stage(content)
        let plan = stage.plan(content)
        stage.globe.setVisited(Set(content.places.map(\.code)))
        stage.globe.renderStill(
            facing: GeoCoordinate(latitude: plan.focus.latitude, longitude: plan.focus.longitude),
            zoom: GlobeTuning.filmZoom,
            offset: StoryLayout.globeOffset,
            into: stage.texture
        )
        let words = StoryHeadline.State(time: plan.duration, countries: content.countries.count, firstCounted: 0, lastCounted: -10, finale: 0)
        let frame = stage.frame(space: stage.backdrop, layers: [
            render(stage.shading, opaque: false),
            render(StoryHeadline(state: words, stats: content.stats, year: stage.year), in: StoryHeadline.frame),
            render(StoryBrand(progress: 1), in: StoryBrand.frame),
        ])
        guard let image = stage.context.createCGImage(frame, from: frame.extent),
              let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.95)
        else { throw StoryFilmError.noGlobe }
        let file = folder.appending(path: "Nomaded.jpg")
        try data.write(to: file)
        log.notice("Story picture in \(CACurrentMediaTime() - started, format: .fixed(precision: 2)) s")
        return StoryPicture(file: file, image: image)
    }

    /// The film. `onProgress` hears how far along it is, 0…1, every frame. Cancelling the
    /// task stops it and keeps nothing.
    static func video(_ content: StoryContent, onProgress: (Double) -> Void) async throws -> URL {
        let started = CACurrentMediaTime()
        let stage = try await Stage(content)
        let plan = stage.plan(content)
        stage.globe.startFilm(
            facing: GeoCoordinate(latitude: plan.opening.latitude, longitude: plan.opening.longitude),
            zoom: GlobeTuning.filmZoom,
            offset: StoryLayout.globeOffset
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Nomaded.mp4")
        try? FileManager.default.removeItem(at: file)
        let video = try VideoWriter(url: file, width: pixels.width, height: pixels.height, framesPerSecond: StoryPlan.framesPerSecond)

        // Drawn once, then only moved, scaled and faded: the same picture every frame.
        let shading = ShadingSprite()
        let scrim = render(StoryScrim(), opaque: false)
        var pins = Pins()
        var headline: (state: StoryHeadline.State, image: CIImage)?
        var brand: (progress: Double, image: CIImage)?
        var nextFill = 0
        var visited: Set<String> = []
        var counted = 0
        var firstCounted: Double?
        var lastCounted = -10.0

        let frames = Int((plan.duration * Double(StoryPlan.framesPerSecond)).rounded())
        let step = 1.0 / Double(StoryPlan.framesPerSecond)
        do {
            for frame in 0..<frames {
                let time = Double(frame) * step
                let shot = plan.shot(at: time)
                let target = GeoCoordinate(latitude: shot.latitude, longitude: shot.longitude)
                // While it flies in, the zoom is the arrival's own; then the tour's.
                if time < StoryPlan.arrival {
                    stage.globe.aim(at: target)
                } else {
                    stage.globe.aim(at: target, zoom: shot.zoom)
                }

                while nextFill < plan.fills.count, plan.fills[nextFill].time <= time {
                    let fill = plan.fills[nextFill]
                    nextFill += 1
                    visited.insert(fill.place.code)
                    stage.globe.setVisited(visited)
                    stage.globe.celebrate(fill.place.code, quietly: !fill.opensStop)
                    pins.pop(fill, at: time, on: stage.globe)
                    if content.countries.contains(fill.place.code) {
                        counted += 1
                        firstCounted = firstCounted ?? time
                        lastCounted = time
                    }
                }

                stage.globe.renderFilmFrame(deltaTime: step, into: stage.texture)

                let state = StoryHeadline.State(time: time, countries: counted, firstCounted: firstCounted, lastCounted: lastCounted, finale: plan.finale)
                if headline?.state != state {
                    headline = (state, render(StoryHeadline(state: state, stats: content.stats, year: stage.year), in: StoryHeadline.frame))
                }
                let progress = StoryTiming.reveal(plan.finale + StoryTiming.brandAfterFinale, at: time)
                if progress > 0, brand?.progress != progress {
                    brand = (progress, render(StoryBrand(progress: progress), in: StoryBrand.frame))
                }
                let space = time < WarpField.duration
                    ? render(StoryWarp(time: time), opaque: false).composited(over: stage.backdrop)
                    : stage.backdrop
                let camera = stage.globe.camera
                // Up close the globe runs under the words: the top of the frame darkens.
                let closeness = camera.silhouetteRadius / stage.wholeRadius
                let image = stage.frame(space: space, layers: [
                    shading.placed(center: camera.center, radius: camera.silhouetteRadius),
                    pins.layer(at: time, on: stage.globe),
                    faded(scrim, by: smoothstep((closeness - 1.25) / 0.75)),
                    headline?.image,
                    brand?.image,
                ].compactMap { $0 })
                try await video.append(image, context: stage.context, colorSpace: sRGB)

                onProgress(Double(frame + 1) / Double(frames))
                // Lets the screen draw between frames, and stops here if cancelled.
                await Task.yield()
                try Task.checkCancellation()
            }
            try await video.finish()
        } catch {
            video.cancel()
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        log.notice("Story video, \(frames) frames, in \(CACurrentMediaTime() - started, format: .fixed(precision: 1)) s")
        return file
    }

    /// A SwiftUI layer as one frame's image, at the film's size.
    private static func render(_ view: some View, opaque: Bool) -> CIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        renderer.isOpaque = opaque
        return renderer.cgImage.map { CIImage(cgImage: $0) } ?? CIImage.empty()
    }

    /// A view of its own size, as an image with its corner at the origin.
    private static func render(_ view: some View, size: CGSize) -> CIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage.map { CIImage(cgImage: $0) } ?? CIImage.empty()
    }

    /// `image` at `opacity`, 0…1. `nil` once it's gone.
    private static func faded(_ image: CIImage, by opacity: Double) -> CIImage? {
        guard opacity > 0.005 else { return nil }
        guard opacity < 0.995 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
    }

    /// 0 below 0, 1 above 1, an S between.
    private static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Where a point of the frame (points, top down) is in pixels, bottom up as Core Image counts.
    private static func pixels(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: (size.height - point.y) * scale)
    }

    /// A strip of the frame (`frame` in points, top down), placed where it belongs.
    private static func render(_ view: some View, in frame: CGRect) -> CIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(frame.size)
        guard let image = renderer.cgImage else { return CIImage.empty() }
        // Core Image counts pixels from the bottom.
        let bottom = (size.height - frame.maxY) * scale
        return CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: frame.minX * scale, y: bottom))
    }

    /// The globe and what every frame is made with.
    @MainActor
    private struct Stage {
        let globe: GlobeController
        let texture: MTLTexture
        let context: CIContext
        let backdrop: CIImage
        let year = Calendar.current.component(.year, from: .now)

        init(_ content: StoryContent) async throws {
            globe = GlobeController(style: .nomaded)
            globe.setViewportSize(StoryFilm.size)
            await globe.load(content.world, worldview: content.worldview)
            guard globe.isReady, let device = globe.device else { throw StoryFilmError.noGlobe }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: GlobeRenderer.pixelFormat, width: StoryFilm.pixels.width, height: StoryFilm.pixels.height, mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw StoryFilmError.noGlobe }
            self.texture = texture
            // Blending in sRGB, as SwiftUI and Core Animation do: in linear light the glow
            // and the shading over the globe come out far stronger than on screen.
            context = CIContext(mtlDevice: device, options: [.workingColorSpace: StoryFilm.sRGB])
            backdrop = StoryFilm.render(StoryBackdrop(), opaque: true)
            globe.setCities(content.cities)
        }

        /// The globe's shading, where the globe is now.
        var shading: StoryShading {
            StoryShading(center: globe.camera.center, radius: globe.camera.silhouetteRadius)
        }

        /// The globe's radius on screen when the whole planet shows.
        var wholeRadius: Double {
            GlobeTuning.baseDiameter(in: StoryFilm.size) / 2 * GlobeTuning.filmZoom
        }

        /// The script for this globe: its zooms are this frame's.
        func plan(_ content: StoryContent) -> StoryPlan {
            StoryPlan(places: content.places, wholeZoom: GlobeTuning.filmZoom, zoomFitting: globe.filmZoom(fitting:))
        }

        /// The globe as last drawn, over `space`, under `layers` (bottom first).
        func frame(space: CIImage, layers: [CIImage]) -> CIImage {
            // Metal's rows run top down, Core Image's bottom up.
            let planet = CIImage(mtlTexture: texture, options: [.colorSpace: StoryFilm.sRGB])?.oriented(.downMirrored) ?? CIImage.empty()
            return layers.reduce(planet.composited(over: space)) { $1.composited(over: $0) }
        }
    }

    /// The globe's shading and glow, drawn once, big. They scale with the globe and
    /// nothing else, so each frame only moves and scales this one picture: no redrawing
    /// as the camera zooms in and out.
    @MainActor
    private struct ShadingSprite {
        /// The globe's radius in the picture, in points: bigger than it ever gets in a frame
        /// but the closest, so it's scaled down far more often than up.
        private static let radius = 240.0
        /// The glow reaches 1.45 radii out.
        private static let side = radius * 2 * 1.5

        private let image: CIImage

        init() {
            let side = Self.side
            image = StoryFilm.render(
                GlobeShading(radius: Self.radius, center: CGPoint(x: side / 2, y: side / 2)).frame(width: side, height: side),
                size: CGSize(width: side, height: side)
            )
        }

        /// The shading for a globe this big, here (points, top down).
        func placed(center: CGPoint, radius: Double) -> CIImage {
            let middle = Self.side * StoryFilm.scale / 2
            let target = StoryFilm.pixels(center)
            return image.transformed(by: CGAffineTransform(translationX: -middle, y: -middle)
                .concatenating(CGAffineTransform(scaleX: radius / Self.radius, y: radius / Self.radius))
                .concatenating(CGAffineTransform(translationX: target.x, y: target.y)))
        }
    }

    /// The flags on the tour: each pops up on its country as it fills, rides along on the
    /// globe and goes as the camera moves on. Each country's is drawn once.
    @MainActor
    private struct Pins {
        private struct Pin {
            let code: String
            let place: GeoCoordinate
            let born: Double
            let departure: Double
        }

        /// A new flag closer than this (points) to one already up stays down: in a crowd the
        /// country still fills and counts, without a pile of flags.
        private static let spacing = 24.0
        private static let fadeOut = 0.3

        private var pins: [Pin] = []
        private var images: [String: CIImage] = [:]

        mutating func pop(_ fill: StoryPlan.Fill, at time: Double, on globe: GlobeController) {
            let place = GeoCoordinate(latitude: fill.place.latitude, longitude: fill.place.longitude)
            guard let new = globe.screenPoint(of: place) else { return }
            let crowded = pins.contains { pin in
                guard time < pin.departure, let point = globe.screenPoint(of: pin.place)?.point else { return false }
                return hypot(point.x - new.point.x, point.y - new.point.y) < Self.spacing
            }
            guard !crowded else { return }
            if images[fill.place.code] == nil {
                images[fill.place.code] = StoryFilm.render(StoryPin(flag: RegionDisplay.flag(for: fill.place.code)), size: StoryPin.size)
            }
            pins.append(Pin(code: fill.place.code, place: place, born: time, departure: fill.departure))
        }

        /// The flags up at `time`, standing where their countries are now. `nil` with none.
        mutating func layer(at time: Double, on globe: GlobeController) -> CIImage? {
            pins.removeAll { time > $0.departure + Self.fadeOut }
            let tip = CGPoint(x: StoryPin.tip.x * StoryFilm.scale, y: (StoryPin.size.height - StoryPin.tip.y) * StoryFilm.scale)
            var layer: CIImage?
            for pin in pins {
                guard let image = images[pin.code], let spot = globe.screenPoint(of: pin.place) else { continue }
                let age = time - pin.born
                // In quickly, out as the camera leaves, and gone over the horizon.
                let opacity = min(1, age / 0.08)
                    * (1 - StoryFilm.smoothstep((time - pin.departure) / Self.fadeOut))
                    * StoryFilm.smoothstep((spot.facing - 0.12) / 0.2)
                let size = max(0.01, StoryPin.scale(age: age))
                let target = StoryFilm.pixels(spot.point)
                guard let placed = StoryFilm.faded(image.transformed(by: CGAffineTransform(translationX: -tip.x, y: -tip.y)
                    .concatenating(CGAffineTransform(scaleX: size, y: size))
                    .concatenating(CGAffineTransform(translationX: target.x, y: target.y))), by: opacity)
                else { continue }
                layer = layer.map(placed.composited(over:)) ?? placed
            }
            return layer
        }
    }
}

/// H.264 in an MP4: what every app that takes stories plays. No sound.
@MainActor
private final class VideoWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let framesPerSecond: Int32
    private var frame: Int64 = 0

    init(url: URL, width: Int, height: Int, framesPerSecond: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // The index up front, as apps that post video expect it.
        writer.shouldOptimizeForNetworkUse = true
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        self.framesPerSecond = Int32(framesPerSecond)
        guard writer.canAdd(input) else { throw StoryFilmError.noVideo }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? StoryFilmError.noVideo }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CIImage, context: CIContext, colorSpace: CGColorSpace) async throws {
        guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? StoryFilmError.noVideo }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw StoryFilmError.noVideo }
        context.render(image, to: buffer, bounds: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)), colorSpace: colorSpace)
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(2))
        }
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: framesPerSecond)) else {
            throw writer.error ?? StoryFilmError.noVideo
        }
        frame += 1
    }

    func finish() async throws {
        input.markAsFinished()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            writer.finishWriting { done.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? StoryFilmError.noVideo }
    }

    func cancel() {
        guard writer.status == .writing else { return }
        writer.cancelWriting()
    }
}
