#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - In-app browser transition: Liquid Glass lens warp

/// Refracts the post→drawer seam and the page card's rim while the browser transition moves.
/// `strength` is 0 when idle (the effect is disabled entirely then), up to 1 mid-transition / fast drags.
[[ stitchable ]] half4 modulaGlassWarp(float2 position, SwiftUI::Layer layer, float2 size, float seamY, float strength, float radius) {
    float dy = position.y - seamY;
    float w = exp(-(dy * dy) / (2.0 * radius * radius));
    // Rim of the page card (left/right edges above the seam) bulges like the edge of a lens.
    float edge = min(position.x, size.x - position.x);
    float we = exp(-(edge * edge) / (2.0 * 14.0 * 14.0)) * step(position.y, seamY);
    float k = 0.38 * strength * w;
    float ke = 0.10 * strength * we;
    float cx = size.x * 0.5;
    float2 base = float2(cx + (position.x - cx) * (1.0 - ke), seamY + dy * (1.0 - k));
    // Chromatic fringe: red and blue refract slightly differently along the lens normal.
    float2 fringe = float2(sign(position.x - cx) * 1.6 * strength * we, sign(dy) * 2.4 * strength * w);
    half4 g = layer.sample(base);
    half4 r = layer.sample(base + fringe);
    half4 b = layer.sample(base - fringe);
    return half4(r.r, g.g, b.b, g.a);
}

// MARK: - Home feed: rows flow around the Edge Picker bulge

/// 0 outside the carved silhouette, 1 in the straight channel, smooth S-curves between
/// (fractions = curveStart, channelStart, channelEnd, curveEnd — same as EdgeLoopShape).
static float modulaBulgeProfile(float t, float4 f) {
    float up = smoothstep(f.x, f.y, t);
    float down = 1.0 - smoothstep(f.z, f.w, t);
    return clamp(min(up, down), 0.0, 1.0);
}

/// Pre-scale distortion. The row is also scaled horizontally by `row.z` (its minimum
/// squeeze, which keeps hit-testing aligned); this adds the remaining per-line squeeze so
/// the final x of every line is x * (width - depth(y)) / width, following the bulge curve.
/// bulge = (globalTop, height, depth, side: 1 trailing / -1 leading); row = (globalTop, width, rowScale)
[[ stitchable ]] float2 modulaEdgeFlow(float2 position, float4 bulge, float4 fractions, float3 row) {
    float t = (row.x + position.y - bulge.x) / max(bulge.y, 1.0);
    float d = bulge.z * modulaBulgeProfile(t, fractions);
    float width = max(row.y, 1.0);
    float s = max((width - d) / width, 0.5);
    float ratio = row.z / s;
    if (bulge.w > 0.0) {
        return float2(position.x * ratio, position.y);
    }
    float fromTrailing = width - position.x;
    return float2(width - fromTrailing * ratio, position.y);
}
