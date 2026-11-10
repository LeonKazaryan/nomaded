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
    /// The screen's outlines and borders, borrowed: the film needn't load them again.
    let world: WorldGeometry
    let worldview: Worldview
}

/// A finished story: the film, and its last frame as a picture.
struct StoryFiles: Equatable {
    let video: URL
    let image: URL
}

enum StoryFilmError: Error {
    case noGlobe
    case noVideo
}

/// Films the user's world for a story (ADR-019): a globe of its own, offscreen, plays
/// `StoryPlan` frame by frame (out of hyperspace, across the places, each filling as it
/// comes round) under the counter and over deep space, into a 1080×1920 video at 30 fps.
/// The frames come as fast as the phone draws them, not in real time.
@MainActor
enum StoryFilm {
    /// A frame in points. Drawn at 3×: 1080×1920, the size stories are made for.
    static let size = CGSize(width: 360, height: 640)
    static let scale = 3.0
    private static let pixels = (width: 1080, height: 1920)
    /// Every this many frames, one goes to the screen while the rest are made. Each one
    /// waits for the GPU, so not too often.
    private static let previewEvery = 6

    private static let log = Logger(subsystem: "com.leonkazaryan.nomaded", category: "Story")

    /// Makes the film and the picture. Every few frames `onFrame` hears the progress, 0…1,
    /// with a small frame to show meanwhile. Cancelling the task stops it and keeps nothing.
    static func make(_ content: StoryContent, onFrame: (Double, CGImage?) -> Void) async throws -> StoryFiles {
        let started = CACurrentMediaTime()
        let plan = StoryPlan(places: content.places)
        let globe = GlobeController(style: .nomaded)
        globe.setViewportSize(size)
        await globe.load(content.world, worldview: content.worldview)
        guard globe.isReady, let device = globe.device, let texture = makeTexture(device) else { throw StoryFilmError.noGlobe }
        globe.setCities(content.cities)
        globe.startFilm(
            facing: GeoCoordinate(latitude: plan.latitude, longitude: plan.longitude(at: 0)),
            zoom: GlobeTuning.filmZoom,
            offset: StoryLayout.globeOffset
        )

        let folder = URL.temporaryDirectory.appending(path: "Story", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = StoryFiles(video: folder.appending(path: "Nomaded.mp4"), image: folder.appending(path: "Nomaded.jpg"))
        let video = try VideoWriter(url: files.video, width: pixels.width, height: pixels.height, framesPerSecond: StoryPlan.framesPerSecond)

        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        // Blending in sRGB, as SwiftUI and Core Animation do: in linear light the glow and
        // the shading over the globe come out far stronger than on screen.
        let context = CIContext(mtlDevice: device, options: [.workingColorSpace: sRGB])
        let year = Calendar.current.component(.year, from: .now)
        let backdrop = render(StoryBackdrop(), opaque: true)
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
                globe.aim(at: GeoCoordinate(latitude: plan.latitude, longitude: plan.longitude(at: time)))

                // Places fill as the globe brings them round; whatever's left once the turn
                // is over fills then. A crowd (Europe) comes a few a frame, never all at once.
                if time >= StoryPlan.sweep.lowerBound {
                    let due = time > StoryPlan.sweep.upperBound ? plan.places : plan.reached(atLongitude: globe.facingLongitude)
                    for place in due where queued.insert(place.code).inserted {
                        waiting.append(place)
                    }
                }
                let release = waiting.isEmpty ? 0 : max(1, waiting.count / 6)
                for place in waiting.prefix(release) {
                    visited.insert(place.code)
                    globe.setVisited(visited)
                    globe.celebrate(place.code, quietly: true)
                    if content.countries.contains(place.code) {
                        counted += 1
                        firstCounted = firstCounted ?? time
                        lastCounted = time
                    }
                }
                waiting.removeFirst(release)

                globe.renderFilmFrame(deltaTime: step, into: texture)
                guard let planet = CIImage(mtlTexture: texture, options: [.colorSpace: sRGB]) else { continue }

                let layer = StoryShading(center: globe.camera.center, radius: globe.camera.silhouetteRadius)
                if shading?.layer != layer {
                    shading = (layer, render(layer, opaque: false))
                }
                let state = StoryHeadline.State(time: time, countries: counted, firstCounted: firstCounted, lastCounted: lastCounted)
                if headline?.state != state {
                    headline = (state, render(StoryHeadline(state: state, stats: content.stats, year: year), in: StoryHeadline.frame))
                }
                let progress = StoryTiming.reveal(StoryTiming.brand, at: time)
                if progress > 0, brand?.progress != progress {
                    brand = (progress, render(StoryBrand(progress: progress), in: StoryBrand.frame))
                }
                let space = time < WarpField.duration ? render(StoryWarp(time: time), opaque: false).composited(over: backdrop) : backdrop
                // Metal's rows run top down, Core Image's bottom up.
                var image = planet.oriented(.downMirrored).composited(over: space)
                for layer in [shading?.image, headline?.image, brand?.image].compactMap({ $0 }) {
                    image = layer.composited(over: image)
                }
                let written = try await video.append(image, context: context, colorSpace: sRGB)

                // The preview comes from the frame just written: drawing the layers again
                // would cost as much as the film itself.
                if frame % previewEvery == 0 || frame == frames - 1 {
                    let small = CIImage(cvPixelBuffer: written, options: [.colorSpace: sRGB])
                        .transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
                    onFrame(Double(frame + 1) / Double(frames), context.createCGImage(small, from: small.extent))
                }
                // Lets the screen draw between frames, and stops here if cancelled.
                await Task.yield()
                try Task.checkCancellation()
            }
            try await video.finish()
        } catch {
            video.cancel()
            try? FileManager.default.removeItem(at: folder)
            throw error
        }

        // The picture: everything filled and every number in, turned to where most of the
        // places are. A second and a half more of film, never shown, lets the turn settle.
        let focus = GeoCoordinate(latitude: plan.focus.latitude, longitude: plan.focus.longitude)
        for _ in 0..<45 {
            globe.aim(at: focus)
            globe.renderFilmFrame(deltaTime: step, into: texture)
        }
        let state = StoryHeadline.State(time: StoryPlan.duration, countries: counted, firstCounted: 0, lastCounted: -10)
        guard let planet = CIImage(mtlTexture: texture, options: [.colorSpace: sRGB]) else { throw StoryFilmError.noGlobe }
        let finale = render(StoryBrand(progress: 1), in: StoryBrand.frame)
            .composited(over: render(StoryHeadline(state: state, stats: content.stats, year: year), in: StoryHeadline.frame))
            .composited(over: render(StoryShading(center: globe.camera.center, radius: globe.camera.silhouetteRadius), opaque: false))
            .composited(over: planet.oriented(.downMirrored))
            .composited(over: backdrop)
        guard let picture = context.createCGImage(finale, from: finale.extent),
              let data = UIImage(cgImage: picture).jpegData(compressionQuality: 0.95)
        else { throw StoryFilmError.noVideo }
        try data.write(to: files.image)
        let elapsed = CACurrentMediaTime() - started
        log.notice("Story made in \(elapsed, format: .fixed(precision: 1)) s: \(files.video.path)")
        return files
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

    private static func makeTexture(_ device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: GlobeRenderer.pixelFormat, width: pixels.width, height: pixels.height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
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

    /// Writes the frame and returns it as written.
    @discardableResult
    func append(_ image: CIImage, context: CIContext, colorSpace: CGColorSpace) async throws -> CVPixelBuffer {
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
        return buffer
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
