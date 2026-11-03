#include <metal_stdlib>
using namespace metal;

// Mirrors `GlobeRenderer.FrameUniforms`, `.DrawUniforms` and `.Marker`. Positions are
// `float3`, 16 bytes apart like Swift's `SIMD3<Float>`.
struct FrameUniforms {
    float4x4 viewProjection;
    float4x4 rotation;
    /// In points.
    float2 viewport;
    float cameraDistance;
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

// MARK: - City markers

struct Marker {
    /// xyz: on the globe, before rotation, already lifted with its country. w: dot radius in points.
    float4 position;
    /// The country's color, for the rim and the glow.
    float4 color;
    /// x: size multiplier (a landing city starts big). y: landing ring 0…1, below 0 none.
    /// z: highlight 0…1.
    float4 params;
};

struct MarkerFragment {
    float4 position [[position]];
    /// Points from the dot's center.
    float2 local;
    float radius;
    float ripple;
    float highlight;
    float fade;
    float4 color;
};

// A screen-facing quad per city, drawn over the land. Dots past the horizon fade out
// instead of being cut by the depth buffer.
vertex MarkerFragment markerVertex(uint vertexID [[vertex_id]],
                                   uint instanceID [[instance_id]],
                                   const device Marker *markers [[buffer(0)]],
                                   constant FrameUniforms &frame [[buffer(1)]]) {
    Marker marker = markers[instanceID];
    float3 world = (frame.rotation * float4(marker.position.xyz, 1)).xyz;
    float3 toCamera = float3(0, 0, frame.cameraDistance) - world;
    float facing = dot(normalize(world), normalize(toCamera));

    float radius = marker.position.w * marker.params.x * (1 + 0.35 * marker.params.z);
    float ripple = marker.params.y;
    // Room for the glow, and for the landing ring while it spreads.
    float extent = max(radius * 3.2, ripple >= 0 ? radius + 34 : 0);
    float2 corner = float2((vertexID & 1) ? 1 : -1, (vertexID & 2) ? 1 : -1);

    float4 clip = frame.viewProjection * float4(world, 1);
    clip.xy += corner * extent * 2 / frame.viewport * clip.w;

    MarkerFragment out;
    out.position = clip;
    out.local = corner * extent;
    out.radius = radius;
    out.ripple = ripple;
    out.highlight = marker.params.z;
    out.fade = smoothstep(0.0, 0.15, facing);
    out.color = marker.color;
    return out;
}

/// Premultiplied `source` over `destination`.
static float4 over(float4 destination, float3 color, float alpha) {
    return float4(color * alpha, alpha) + destination * (1 - alpha);
}

// White core, a rim in the country's color, a dark hairline so it reads on any land, and
// a soft glow. A landing city also sends out a ring.
fragment float4 markerFragment(MarkerFragment in [[stage_in]]) {
    float r = length(in.local);
    float core = in.radius;
    float3 tint = in.color.rgb;
    float4 result = float4(0);

    float glow = exp(-pow(max(r - core, 0.0) / (core * (1.1 + in.highlight)), 2)) * (0.45 + 0.4 * in.highlight);
    result = over(result, tint, glow * step(core, r));

    if (in.ripple >= 0) {
        float rippleRadius = mix(core, core + 32, in.ripple);
        float ring = 1 - smoothstep(0.6, 1.8, abs(r - rippleRadius));
        result = over(result, mix(float3(1), tint, in.ripple), ring * pow(1 - in.ripple, 1.5));
    }

    float outline = 1 - smoothstep(core + 1.6, core + 2.4, r);
    result = over(result, float3(0.05, 0.04, 0.12), outline * 0.55);
    float rim = 1 - smoothstep(core + 0.6, core + 1.4, r);
    result = over(result, tint, rim);
    float inner = 1 - smoothstep(core * 0.62 - 0.5, core * 0.62 + 0.5, r);
    result = over(result, float3(1), inner);

    return result * in.fade;
}
