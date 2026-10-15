#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// MOL-03 polish v2: Moliboo shader kit. Single pass, no loops over the layer, at most one layer sample.
// `time` is wrapped by MolibooShaderClock; every effect has a static (time = 0) look for Reduce Motion.

static inline float mbHash(float2 p) { p = fract(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
static inline float mbNoise(float2 p) {
    float2 i = floor(p), f = fract(p); float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(mbHash(i), mbHash(i + float2(1, 0)), u.x), mix(mbHash(i + float2(0, 1)), mbHash(i + float2(1, 1)), u.x), u.y);
}
static inline float mbFbm(float2 p) { float v = 0, a = 0.5; for (int i = 0; i < 4; i++) { v += a * mbNoise(p); p *= 2.03; a *= 0.5; } return v; }
static inline half3 mbHue(float h) { return half3(clamp(abs(fmod(h * 6.0 + float3(0, 4, 2), 6.0) - 3.0) - 1.0, 0.0, 1.0)); }

/// Holographic foil over a card: rainbow bands that slide with tilt + time, masked to the card's own alpha.
[[ stitchable ]] half4 molibooHoloFoil(float2 position, half4 color, float2 size, float time, float2 tilt, float strength) {
    if (color.a < 0.01) return color;
    float2 uv = position / max(size, float2(1));
    float band = uv.x * 1.4 + uv.y * 0.9 + tilt.x * 0.6 + tilt.y * 0.4 + time * 0.12;
    half3 foil = mbHue(fract(band));
    float sparkle = step(0.985, mbHash(floor(position / 3.0) + floor(time * 4.0)));
    float sheen = pow(max(0.0, 1.0 - abs(fract(band * 0.5) - 0.5) * 4.0), 3.0);
    half3 c = color.rgb + foil * half(strength * (0.18 + 0.35 * sheen)) + half3(sparkle * strength * 0.8);
    return half4(min(c, half3(color.a)), color.a);
}

/// Moving water caustics + soft glow for the pedestal (premultiplied, additive-friendly).
[[ stitchable ]] half4 molibooCaustics(float2 position, half4 color, float2 size, float time, half4 tint) {
    if (color.a < 0.01) return color;
    float2 uv = position / max(size, float2(1)) * float2(6.0, 3.0);
    float n = mbFbm(uv + float2(time * 0.25, -time * 0.18));
    float m = mbFbm(uv * 1.7 - float2(time * 0.2, time * 0.12));
    float caustic = pow(1.0 - abs(n - m) * 3.0, 6.0);
    half3 c = color.rgb + tint.rgb * half(caustic * 0.55) * color.a;
    return half4(c, color.a);
}

/// Nebula / aurora night sky: layered fbm clouds in purple-teal over the incoming colour.
[[ stitchable ]] half4 molibooNebula(float2 position, half4 color, float2 size, float time, float intensity) {
    float2 uv = position / max(size, float2(1));
    float2 p = uv * float2(3.0, 2.0);
    float a = mbFbm(p + float2(time * 0.02, 0) + mbFbm(p * 0.7 + time * 0.015));
    float ribbon = smoothstep(0.15, 0.0, abs(uv.y - 0.25 - 0.08 * sin(uv.x * 5.0 + time * 0.3))) * (0.6 + 0.4 * mbNoise(float2(uv.x * 8.0 + time * 0.4, 0)));
    half3 neb = mix(half3(0.35, 0.18, 0.65), half3(0.10, 0.65, 0.70), half(a)) * half(smoothstep(0.35, 0.85, a));
    half3 aur = half3(0.25, 0.95, 0.65) * half(ribbon * (1.0 - uv.y));
    // Emissive: works over a clear layer too (premultiplied output, alpha = brightest channel).
    half3 e = (neb * 0.55 + aur * 0.45) * half(intensity);
    return half4(color.rgb + e, max(color.a, max(e.r, max(e.g, e.b))));
}

/// Tap ripple: radial sine displacement that decays with distance and age (distortion effect).
[[ stitchable ]] float2 molibooRipple(float2 position, float2 origin, float age, float amplitude) {
    float d = distance(position, origin);
    float wave = sin(d * 0.09 - age * 14.0) * exp(-age * 3.0) * exp(-d * 0.012);
    float2 dir = d > 0.0 ? (position - origin) / d : float2(0);
    return position + dir * wave * amplitude * step(0.0, age) * step(age, 1.6);
}

/// Shimmer sweep for Legendary items / cards: a bright diagonal band crossing every ~3 s.
[[ stitchable ]] half4 molibooShimmer(float2 position, half4 color, float2 size, float time, float strength) {
    if (color.a < 0.01) return color;
    float2 uv = position / max(size, float2(1));
    float x = fract(time / 3.0) * 2.6 - 0.8;
    float band = exp(-pow((uv.x + uv.y * 0.6 - x) * 7.0, 2.0));
    half3 c = color.rgb + half3(1.0, 0.95, 0.75) * half(band * strength) * color.a;
    return half4(min(c, half3(color.a)), color.a);
}

/// Pack opening: the foil wrapper burns away from the centre with a glowing edge (layer effect, `progress` 0→1).
[[ stitchable ]] half4 molibooPackReveal(float2 position, SwiftUI::Layer layer, float2 size, float progress) {
    half4 c = layer.sample(position);
    float2 uv = position / max(size, float2(1));
    float n = mbFbm(uv * 5.0);
    float d = distance(uv, float2(0.5)) * 1.3 + n * 0.35;
    float edge = progress * 1.7;
    if (d < edge - 0.06) return half4(0);
    float glow = smoothstep(edge + 0.06, edge, d);
    half3 hot = half3(1.0, 0.8, 0.4) * half(glow * 1.4);
    return half4(c.rgb + hot * c.a, c.a);
}
