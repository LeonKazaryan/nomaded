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
/// at once. The film plays `StoryPlan` frame by frame (out of hyperspace, across the places,
/// each filling as it comes round) into a video at 30 fps: as fast as the phone draws, not in
/// real time, and only when asked for.
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
        let plan = StoryPlan(places: content.places)
        let stage = try await Stage(content)
        stage.globe.setVisited(Set(content.places.map(\.code)))
        stage.globe.renderStill(
            facing: GeoCoordinate(latitude: plan.focus.latitude, longitude: plan.focus.longitude),
            zoom: GlobeTuning.filmZoom,
            offset: StoryLayout.globeOffset,
            into: stage.texture
        )
        let words = StoryHeadline.State(time: StoryPlan.duration, countries: content.countries.count, firstCounted: 0, lastCounted: -10)
        let frame = stage.frame(
            space: stage.backdrop,
            shading: render(stage.shading, opaque: false),
            headline: render(StoryHeadline(state: words, stats: content.stats, year: stage.year), in: StoryHeadline.frame),
            brand: render(StoryBrand(progress: 1), in: StoryBrand.frame)
        )
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
        let plan = StoryPlan(places: content.places)
        let stage = try await Stage(content)
        stage.globe.startFilm(
            facing: GeoCoordinate(latitude: plan.latitude, longitude: plan.longitude(at: 0)),
            zoom: GlobeTuning.filmZoom,
            offset: StoryLayout.globeOffset
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Nomaded.mp4")
        try? FileManager.default.removeItem(at: file)
        let video = try VideoWriter(url: file, width: pixels.width, height: pixels.height, framesPerSecond: StoryPlan.framesPerSecond)

        var shading: (layer: StoryShading, image: CIImage)?
        var headline: (state: StoryHeadline.State, image: CIImage)?
        var brand: (progress: Double, image: CIImage)?
        var queued: Set<String> = []
        var waiting: [StoryPlan.Place] = []
        var visited: Set<String> = []
        var counted = 0
        var firstCounted: Double?
        var lastCounted = -10.0

        let frames = Int(StoryPlan.duration * Double(StoryPlan.framesPerSecond))
        let step = 1.0 / Double(StoryPlan.framesPerSecond)
        do {
            for frame in 0..<frames {
                let time = Double(frame) * step
                stage.globe.aim(at: GeoCoordinate(latitude: plan.latitude, longitude: plan.longitude(at: time)))

                // Places fill as the globe brings them round; whatever's left once the turn
                // is over fills then. A crowd (Europe) comes a few a frame, never all at once.
                if time >= StoryPlan.sweep.lowerBound {
                    let due = time > StoryPlan.sweep.upperBound ? plan.places : plan.reached(atLongitude: stage.globe.facingLongitude)
                    for place in due where queued.insert(place.code).inserted {
                        waiting.append(place)
                    }
                }
                let release = waiting.isEmpty ? 0 : max(1, waiting.count / 6)
                for place in waiting.prefix(release) {
                    visited.insert(place.code)
                    stage.globe.setVisited(visited)
                    stage.globe.celebrate(place.code, quietly: true)
                    if content.countries.contains(place.code) {
                        counted += 1
                        firstCounted = firstCounted ?? time
                        lastCounted = time
                    }
                }
                waiting.removeFirst(release)

                stage.globe.renderFilmFrame(deltaTime: step, into: stage.texture)

                // Each layer is drawn again only when it changes.
                if shading?.layer != stage.shading {
                    shading = (stage.shading, render(stage.shading, opaque: false))
                }
                let state = StoryHeadline.State(time: time, countries: counted, firstCounted: firstCounted, lastCounted: lastCounted)
                if headline?.state != state {
                    headline = (state, render(StoryHeadline(state: state, stats: content.stats, year: stage.year), in: StoryHeadline.frame))
                }
                let progress = StoryTiming.reveal(StoryTiming.brand, at: time)
                if progress > 0, brand?.progress != progress {
                    brand = (progress, render(StoryBrand(progress: progress), in: StoryBrand.frame))
                }
                let space = time < WarpField.duration
                    ? render(StoryWarp(time: time), opaque: false).composited(over: stage.backdrop)
                    : stage.backdrop
                let image = stage.frame(space: space, shading: shading?.image, headline: headline?.image, brand: brand?.image)
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
        log.notice("Story video in \(CACurrentMediaTime() - started, format: .fixed(precision: 1)) s")
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

        /// The globe as last drawn, with the layers over and under it.
        func frame(space: CIImage, shading: CIImage?, headline: CIImage?, brand: CIImage?) -> CIImage {
            // Metal's rows run top down, Core Image's bottom up.
            let planet = CIImage(mtlTexture: texture, options: [.colorSpace: StoryFilm.sRGB])?.oriented(.downMirrored) ?? CIImage.empty()
            var image = planet.composited(over: space)
            for layer in [shading, headline, brand].compactMap({ $0 }) {
                image = layer.composited(over: image)
            }
            return image
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
