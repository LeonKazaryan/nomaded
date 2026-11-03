import Metal
import QuartzCore
import simd

enum GlobeRendererError: Error {
    case noMetal
    case noShaders
    case outOfMemory
}

/// Draws the globe with Metal: the ocean, every country at its own lift and color, and side
/// walls under lifted ones. Replaces RealityKit, which never rendered faster than 60 fps on
/// iPhone (ADR-010). This draws as often as the display link asks, up to 120 on ProMotion.
@MainActor
final class GlobeRenderer {
    /// One country as the renderer sees it. The controller writes `scale` and `color` while
    /// the country animates; nothing is rebuilt, so a change costs nothing.
    struct Piece {
        let surface: MeshRange
        var walls: MeshRange?
        /// 1 + lift.
        var scale: Float = 1
        /// The color, or, while `wave` runs, the color inside it.
        var color: SIMD3<Float>
        /// Outside a running wave.
        var previous = SIMD3<Float>(0, 0, 0)
        /// xyz: where a fill wave started, on the unit globe. w: its radius in radians;
        /// below 0, no wave.
        var wave = SIMD4<Float>(0, 0, 0, -1)
        /// x: edge softness, y: front width (radians), z: front brightness.
        var waveStyle = SIMD4<Float>(0, 0, 0, 0)

        /// Walls only show once the country rises off the globe.
        var showsWalls: Bool { scale > 1.0005 }
    }

    /// A city dot, drawn over the land. Mirrors `Marker` in GlobeShaders.metal.
    struct Marker {
        /// xyz: on the globe before rotation, lifted with its country. w: radius in points.
        var position: SIMD4<Float>
        var color: SIMD4<Float>
        /// x: size multiplier, y: landing ring 0…1 (below 0: none), z: highlight 0…1,
        /// w: 1 for a capital, drawn as a star.
        var params: SIMD4<Float>
    }

    // Mirror the structs in GlobeShaders.metal.
    private struct FrameUniforms {
        var viewProjection: simd_float4x4
        var rotation: simd_float4x4
        var viewport: SIMD2<Float>
        var cameraDistance: Float
        var ring: SIMD4<Float>
        var ringColor: SIMD4<Float>
    }

    private struct DrawUniforms {
        var color: SIMD4<Float>
        var previous: SIMD4<Float>
        var wave: SIMD4<Float>
        var waveStyle: SIMD4<Float>
        var scale: Float
    }

    private struct GPUMesh {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
    }

    static let pixelFormat = MTLPixelFormat.bgra8Unorm
    private static let depthFormat = MTLPixelFormat.depth32Float
    /// 4× MSAA keeps coastlines and the globe's outline smooth.
    private static let sampleCount = 4

    let device: MTLDevice
    var pieces: [Piece] = []
    var markers: [Marker] = []
    var oceanColor = SIMD3<Float>(0, 0, 0)
    /// The ring a newly marked country sends around the planet. xyz: start on the unit
    /// globe, w: distance travelled in radians (below 0: none).
    var ring = SIMD4<Float>(0, 0, 0, -1)
    /// rgb and strength.
    var ringColor = SIMD4<Float>(0, 0, 0, 0)

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let markerPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    /// Markers sit on top of the land and fade at the horizon themselves.
    private let overlayDepthState: MTLDepthStencilState
    /// One per frame in flight: the CPU fills the next while the GPU reads the others.
    /// Three drawables means at most three frames in flight.
    private var markerBuffers: [MTLBuffer] = []
    private var markerBufferIndex = 0
    private var ocean: GPUMesh?
    private var land: GPUMesh?
    private var walls: GPUMesh?
    private var targets: (color: MTLTexture, depth: MTLTexture)?

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw GlobeRendererError.noMetal
        }
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "globeVertex"),
              let fragment = library.makeFunction(name: "globeFragment"),
              let markerVertex = library.makeFunction(name: "markerVertex"),
              let markerFragment = library.makeFunction(name: "markerFragment")
        else { throw GlobeRendererError.noShaders }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
        descriptor.depthAttachmentPixelFormat = Self.depthFormat
        descriptor.rasterSampleCount = Self.sampleCount

        let markers = MTLRenderPipelineDescriptor()
        markers.vertexFunction = markerVertex
        markers.fragmentFunction = markerFragment
        markers.colorAttachments[0].pixelFormat = Self.pixelFormat
        markers.colorAttachments[0].isBlendingEnabled = true
        // The fragment shader returns premultiplied alpha.
        markers.colorAttachments[0].sourceRGBBlendFactor = .one
        markers.colorAttachments[0].sourceAlphaBlendFactor = .one
        markers.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        markers.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        markers.depthAttachmentPixelFormat = Self.depthFormat
        markers.rasterSampleCount = Self.sampleCount

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        let overlay = MTLDepthStencilDescriptor()
        overlay.depthCompareFunction = .always
        overlay.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depth),
              let overlayDepthState = device.makeDepthStencilState(descriptor: overlay)
        else { throw GlobeRendererError.noMetal }

        self.device = device
        self.queue = queue
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        self.markerPipeline = try device.makeRenderPipelineState(descriptor: markers)
        self.depthState = depthState
        self.overlayDepthState = overlayDepthState
    }

    func setScene(ocean: MeshData, land: MeshData) throws {
        self.ocean = try upload(ocean)
        self.land = try upload(land)
    }

    func setWalls(_ walls: MeshData, ranges: [MeshRange]) throws {
        self.walls = try upload(walls)
        for index in pieces.indices where index < ranges.count {
            pieces[index].walls = ranges[index]
        }
    }

    func draw(in layer: CAMetalLayer, rotation: simd_quatf, camera: GlobeCamera) {
        guard let ocean, let land, camera.viewportSize.width > 0, camera.viewportSize.height > 0,
              let drawable = layer.nextDrawable(),
              let targets = renderTargets(matching: drawable.texture),
              let commandBuffer = queue.makeCommandBuffer()
        else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.color
        pass.colorAttachments[0].resolveTexture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        // Transparent: the SwiftUI space background shows around the globe.
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = targets.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        var frame = FrameUniforms(
            viewProjection: camera.viewProjection,
            rotation: simd_float4x4(rotation),
            viewport: SIMD2(Float(camera.viewportSize.width), Float(camera.viewportSize.height)),
            cameraDistance: Float(camera.distance),
            ring: ring,
            ringColor: ringColor
        )
        encoder.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)

        encoder.setVertexBuffer(ocean.vertices, offset: 0, index: 0)
        draw(MeshRange(indexStart: 0, indexCount: ocean.indexCount), of: ocean, piece: Piece(surface: MeshRange(indexStart: 0, indexCount: 0), color: oceanColor), with: encoder)

        encoder.setVertexBuffer(land.vertices, offset: 0, index: 0)
        for piece in pieces {
            draw(piece.surface, of: land, piece: piece, with: encoder)
        }

        if let walls {
            encoder.setVertexBuffer(walls.vertices, offset: 0, index: 0)
            for piece in pieces where piece.showsWalls {
                guard let range = piece.walls else { continue }
                draw(range, of: walls, piece: piece, shade: GlobeTuning.wallShade, with: encoder)
            }
        }

        drawMarkers(with: encoder)

        encoder.endEncoding()
        if layer.presentsWithTransaction {
            // Lands in the same Core Animation commit as the SwiftUI overlays (city names,
            // shading), so they never trail the globe by a frame.
            commandBuffer.commit()
            commandBuffer.waitUntilScheduled()
            drawable.present()
        } else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    private func drawMarkers(with encoder: MTLRenderCommandEncoder) {
        guard !markers.isEmpty, let buffer = nextMarkerBuffer() else { return }
        markers.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        encoder.setRenderPipelineState(markerPipeline)
        encoder.setDepthStencilState(overlayDepthState)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: markers.count)
    }

    /// The next buffer in the ring, grown to fit every marker.
    private func nextMarkerBuffer() -> MTLBuffer? {
        let length = markers.count * MemoryLayout<Marker>.stride
        if markerBuffers.isEmpty || markerBuffers[0].length < length {
            // Room to spare, so adding a city doesn't reallocate every time.
            let capacity = max(length * 2, 64 * MemoryLayout<Marker>.stride)
            markerBuffers = (0..<3).compactMap { _ in device.makeBuffer(length: capacity, options: .storageModeShared) }
            guard markerBuffers.count == 3 else { return nil }
        }
        markerBufferIndex = (markerBufferIndex + 1) % markerBuffers.count
        return markerBuffers[markerBufferIndex]
    }

    /// `shade` darkens both colors, for walls.
    private func draw(_ range: MeshRange, of mesh: GPUMesh, piece: Piece, shade: Float = 1, with encoder: MTLRenderCommandEncoder) {
        guard range.indexCount > 0 else { return }
        var uniforms = DrawUniforms(
            color: SIMD4(piece.color * shade, 1),
            previous: SIMD4(piece.previous * shade, 1),
            wave: piece.wave,
            waveStyle: piece.waveStyle,
            scale: piece.scale
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 0)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: range.indexCount,
            indexType: .uint32,
            indexBuffer: mesh.indices,
            indexBufferOffset: range.indexStart * MemoryLayout<UInt32>.stride
        )
    }

    private func upload(_ mesh: MeshData) throws -> GPUMesh {
        guard let vertices = device.makeBuffer(
                  bytes: mesh.positions,
                  length: max(1, mesh.positions.count) * MemoryLayout<SIMD3<Float>>.stride,
                  options: .storageModeShared
              ),
              let indices = device.makeBuffer(
                  bytes: mesh.indices,
                  length: max(1, mesh.indices.count) * MemoryLayout<UInt32>.stride,
                  options: .storageModeShared
              )
        else { throw GlobeRendererError.outOfMemory }
        return GPUMesh(vertices: vertices, indices: indices, indexCount: mesh.indices.count)
    }

    /// Multisampled color and depth, remade only when the drawable changes size. On a real
    /// GPU they're memoryless: they live in tile memory and never touch RAM.
    private func renderTargets(matching drawable: MTLTexture) -> (color: MTLTexture, depth: MTLTexture)? {
        if let targets, targets.color.width == drawable.width, targets.color.height == drawable.height {
            return targets
        }
        func target(_ format: MTLPixelFormat) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: drawable.width, height: drawable.height, mipmapped: false
            )
            descriptor.textureType = .type2DMultisample
            descriptor.sampleCount = Self.sampleCount
            descriptor.usage = .renderTarget
            #if targetEnvironment(simulator)
            descriptor.storageMode = .private
            #else
            descriptor.storageMode = .memoryless
            #endif
            return device.makeTexture(descriptor: descriptor)
        }
        guard let color = target(Self.pixelFormat), let depth = target(Self.depthFormat) else { return nil }
        targets = (color, depth)
        return targets
    }
}
