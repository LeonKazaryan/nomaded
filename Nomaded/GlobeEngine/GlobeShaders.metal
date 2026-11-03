#include <metal_stdlib>
using namespace metal;

// Mirrors `GlobeRenderer.FrameUniforms` and `GlobeRenderer.DrawUniforms`. Positions are
// `float3`, 16 bytes apart like Swift's `SIMD3<Float>`.
struct FrameUniforms {
    float4x4 viewProjection;
    float4x4 rotation;
};

struct DrawUniforms {
    float4 color;
    /// 1 + lift: land rises straight up from the globe's center.
    float scale;
};

struct Fragment {
    float4 position [[position]];
};

vertex Fragment globeVertex(uint id [[vertex_id]],
                            const device float3 *positions [[buffer(0)]],
                            constant FrameUniforms &frame [[buffer(1)]],
                            constant DrawUniforms &draw [[buffer(2)]]) {
    float4 world = frame.rotation * float4(positions[id] * draw.scale, 1);
    return { frame.viewProjection * world };
}

// Flat, unlit color. The globe's volume comes from the SwiftUI shading on top, so palette
// colors reach the screen exactly as designed.
fragment float4 globeFragment(constant DrawUniforms &draw [[buffer(0)]]) {
    return draw.color;
}
