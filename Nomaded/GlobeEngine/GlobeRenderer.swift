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
        var color: SIMD3<Float>

        /// Walls only show once the country rises off the globe.
        var showsWalls: Bool { scale > 1.0005 }
    }

    // Mirror the structs in GlobeShaders.metal.
    private struct FrameUniforms {
        var viewProjection: simd_float4x4
        var rotation: simd_float4x4
    }

    private struct DrawUniforms {
        var color: SIMD4<Float>
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
    var oceanColor = SIMD3<Float>(0, 0, 0)

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
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
              let fragment = library.makeFunction(name: "globeFragment")
        else { throw GlobeRendererError.noShaders }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
        descriptor.depthAttachmentPixelFormat = Self.depthFormat
        descriptor.rasterSampleCount = Self.sampleCount

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { throw GlobeRendererError.noMetal }

        self.device = device
        self.queue = queue
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        self.depthState = depthState
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
        var frame = FrameUniforms(viewProjection: camera.viewProjection, rotation: simd_float4x4(rotation))
        encoder.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)

        encoder.setVertexBuffer(ocean.vertices, offset: 0, index: 0)
        draw(MeshRange(indexStart: 0, indexCount: ocean.indexCount), of: ocean, color: oceanColor, scale: 1, with: encoder)

        encoder.setVertexBuffer(land.vertices, offset: 0, index: 0)
        for piece in pieces {
            draw(piece.surface, of: land, color: piece.color, scale: piece.scale, with: encoder)
        }

        if let walls {
            encoder.setVertexBuffer(walls.vertices, offset: 0, index: 0)
            for piece in pieces where piece.showsWalls {
                guard let range = piece.walls else { continue }
                draw(range, of: walls, color: piece.color * GlobeTuning.wallShade, scale: piece.scale, with: encoder)
            }
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func draw(_ range: MeshRange, of mesh: GPUMesh, color: SIMD3<Float>, scale: Float, with encoder: MTLRenderCommandEncoder) {
        guard range.indexCount > 0 else { return }
        var uniforms = DrawUniforms(color: SIMD4(color, 1), scale: scale)
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
