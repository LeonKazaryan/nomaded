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
    /// The ring a newly marked country sends around the planet. xyz: where it starts, on
    /// the unit globe before rotation. w: how far it has travelled, in radians; below 0, none.
    float4 ring;
    /// rgb: its color. a: its strength, fading to 0.
    float4 ringColor;
};

struct DrawUniforms {
    /// The color, or, while a fill wave runs, the color inside the wave.
    float4 color;
    /// Outside the wave: the color the country is leaving (or, draining, going back to).
    float4 previous;
    /// xyz: where the wave started, on the unit globe before rotation. w: its radius in
    /// radians; below 0, no wave.
    float4 wave;
    /// x: how soft its edge is, y: how wide its bright front, both in radians.
    /// z: how bright that front is.
    float4 waveStyle;
    /// 1 + lift: land rises straight up from the globe's center.
    float scale;
};

struct Fragment {
    float4 position [[position]];
    /// Where on the globe, before rotation: for the wave and the ring.
    float3 local;
};

vertex Fragment globeVertex(uint id [[vertex_id]],
                            const device float3 *positions [[buffer(0)]],
                            constant FrameUniforms &frame [[buffer(1)]],
                            constant DrawUniforms &draw [[buffer(2)]]) {
    float3 local = positions[id] * draw.scale;
    float4 world = frame.rotation * float4(local, 1);
    return { frame.viewProjection * world, local };
}

// Flat, unlit color. The globe's volume comes from the SwiftUI shading on top, so palette
// colors reach the screen exactly as designed. Two effects ride on top: a country's fill
// wave and the ring a marked country sends around the planet.
fragment float4 globeFragment(Fragment in [[stage_in]],
                              constant DrawUniforms &draw [[buffer(0)]],
                              constant FrameUniforms &frame [[buffer(1)]]) {
    float3 p = normalize(in.local);
    float3 color = draw.color.rgb;

    if (draw.wave.w >= 0) {
        float d = acos(clamp(dot(p, draw.wave.xyz), -1.0, 1.0));
        float radius = draw.wave.w;
        float inside = 1 - smoothstep(radius - draw.waveStyle.x, radius + draw.waveStyle.x, d);
        color = mix(draw.previous.rgb, color, inside);
        // A bright band rides the edge of the spreading color.
        float front = exp(-pow((d - radius) / draw.waveStyle.y, 2)) * draw.waveStyle.z;
        color = mix(color, float3(1), clamp(front, 0.0, 1.0));
    }

    if (frame.ring.w >= 0) {
        float d = acos(clamp(dot(p, frame.ring.xyz), -1.0, 1.0));
        float offset = d - frame.ring.w;
        // A sharp line with a soft glow trailing behind it.
        float line = exp(-pow(offset / 0.012, 2));
        float glow = exp(-pow(min(offset, 0.0) / 0.07, 2)) * 0.35;
        color = mix(color, frame.ringColor.rgb, clamp((line + glow) * frame.ringColor.a, 0.0, 1.0));
    }

    return float4(color, 1);
}

// MARK: - City markers

struct Marker {
    /// xyz: on the globe, before rotation, already lifted with its country. w: dot radius in points.
    float4 position;
    /// The country's color, for the rim and the glow.
    float4 color;
    /// x: size multiplier (a landing city starts big). y: landing ring 0…1, below 0 none.
    /// z: highlight 0…1. w: 1 for a capital, drawn as a star.
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
    float star;
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
    // A star's points reach well past a dot's edge.
    float reach = radius * (marker.params.w > 0.5 ? 1.8 : 1);
    // Room for the glow, and for the landing ring while it spreads.
    float extent = max(reach * 3.2, ripple >= 0 ? reach + 34 : 0);
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
    out.star = marker.params.w;
    out.color = marker.color;
    return out;
}

/// Signed distance to a five-pointed star pointing up, in the units of `p`: negative
/// inside. `r` is the tips' radius, `rf` how deep the notches cut (Inigo Quilez's sdStar5).
static float starDistance(float2 p, float r, float rf) {
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0, 1);
    float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

/// Premultiplied `source` over `destination`.
static float4 over(float4 destination, float3 color, float alpha) {
    return float4(color * alpha, alpha) + destination * (1 - alpha);
}

// White core, a rim in the country's color, a dark hairline so it reads on any land, and
// a soft glow. A capital is the same, shaped as a star. A landing city also sends out a ring.
fragment float4 markerFragment(MarkerFragment in [[stage_in]]) {
    float r = length(in.local);
    float core = in.radius;
    // Distance to the shape's edge, in points: negative inside.
    float d = in.star > 0.5 ? starDistance(in.local, core * 1.8, 0.48) : r - core;
    float3 tint = in.color.rgb;
    float4 result = float4(0);

    float glow = exp(-pow(max(d, 0.0) / (core * (1.1 + in.highlight)), 2)) * (0.45 + 0.4 * in.highlight);
    result = over(result, tint, glow * step(0.0, d));

    if (in.ripple >= 0) {
        float rippleRadius = mix(core, core + 32, in.ripple);
        float ring = 1 - smoothstep(0.6, 1.8, abs(r - rippleRadius));
        result = over(result, mix(float3(1), tint, in.ripple), ring * pow(1 - in.ripple, 1.5));
    }

    float outline = 1 - smoothstep(1.6, 2.4, d);
    result = over(result, float3(0.05, 0.04, 0.12), outline * 0.55);
    float rim = 1 - smoothstep(0.6, 1.4, d);
    result = over(result, tint, rim);
    // The white inside, inset from the edge as far as a dot's is.
    float inner = 1 - smoothstep(-0.5, 0.5, d + core * 0.38);
    result = over(result, float3(1), inner);

    return result * in.fade;
}
