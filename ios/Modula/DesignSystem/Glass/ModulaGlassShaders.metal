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

