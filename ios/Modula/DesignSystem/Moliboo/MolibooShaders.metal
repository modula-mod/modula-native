#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// MOL-03R High-Craft Metal Shader Kit.
// Single pass, zero texture loops, at most one layer sample.
// `time` is wrapped by MolibooShaderClock; every effect has a clean static (time = 1.5) look under Reduce Motion.

static inline float mbHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float mbNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(mbHash(i), mbHash(i + float2(1, 0)), u.x),
               mix(mbHash(i + float2(0, 1)), mbHash(i + float2(1, 1)), u.x), u.y);
}

static inline float mbFbm(float2 p) {
    float v = 0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * mbNoise(p);
        p *= 2.03;
        a *= 0.5;
    }
    return v;
}

static inline half3 mbHue(float h) {
    return half3(clamp(abs(fmod(h * 6.0 + float3(0, 4, 2), 6.0) - 3.0) - 1.0, 0.0, 1.0));
}

/// Upgraded holographic prismatic foil over a card: rainbow bands + micro-diamond facets that respond to tilt + time.
[[ stitchable ]] half4 molibooHoloFoil(float2 position, half4 color, float2 size, float time, float2 tilt, float strength) {
    if (color.a < 0.01h) return color;
    float2 uv = position / max(size, float2(1.0));
    float angle = uv.x * 1.45 + uv.y * 0.95 + tilt.x * 0.75 + tilt.y * 0.55 + time * 0.14;
    half3 foil = mix(mbHue(fract(angle)), half3(0.45h, 0.92h, 0.98h), 0.22h);
    float2 cell = floor(position / 3.5);
    float sparkle = step(0.982, mbHash(cell + floor(time * 4.5) + floor(tilt * 6.0)));
    float sheen = pow(max(0.0, 1.0 - abs(fract(angle * 0.55) - 0.5) * 3.6), 2.6);
    float rim = smoothstep(0.32, 0.50, max(abs(uv.x - 0.5), abs(uv.y - 0.5)));
    half3 add = foil * half(strength * (0.20 + 0.38 * sheen + 0.22 * rim)) + half3(sparkle * strength * 0.85);
    return half4(min(color.rgb + add * color.a, half3(color.a)), color.a);
}

/// Moving water/moss caustics + bioluminescent rim glow for the pedestal.
[[ stitchable ]] half4 molibooCaustics(float2 position, half4 color, float2 size, float time, half4 tint) {
    if (color.a < 0.01h) return color;
    float2 uv = position / max(size, float2(1.0));
    float2 p = uv * float2(6.0, 3.2);
    float n = mbFbm(p + float2(time * 0.26, -time * 0.18));
    float m = mbFbm(p * 1.75 - float2(time * 0.21, time * 0.14));
    float caustic = pow(max(0.0, 1.0 - abs(n - m) * 2.8), 5.0);
    float edgeGlow = smoothstep(0.5, 0.12, length(uv - float2(0.5)));
    half3 c = color.rgb + tint.rgb * half((caustic * 0.58 + edgeGlow * 0.16)) * color.a;
    return half4(min(c, half3(color.a)), color.a);
}

/// Nebula / aurora night sky: layered fbm clouds + dual dancing aurora ribbons in Modula teal and violet.
[[ stitchable ]] half4 molibooNebula(float2 position, half4 color, float2 size, float time, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float2 p = uv * float2(3.0, 2.0);
    float a = mbFbm(p + float2(time * 0.022, 0.0) + mbFbm(p * 0.72 + time * 0.016));
    float wave1 = uv.y - 0.24 - 0.075 * sin(uv.x * 5.2 + time * 0.32) - 0.03 * cos(uv.x * 9.0 - time * 0.2);
    float ribbon1 = smoothstep(0.15, 0.0, abs(wave1)) * (0.55 + 0.45 * mbNoise(float2(uv.x * 8.5 + time * 0.4, 1.0)));
    float wave2 = uv.y - 0.36 - 0.055 * cos(uv.x * 4.1 - time * 0.24);
    float ribbon2 = smoothstep(0.12, 0.0, abs(wave2)) * (0.5 + 0.5 * mbNoise(float2(uv.x * 6.5 - time * 0.3, 3.0)));
    half3 neb = mix(half3(0.36h, 0.18h, 0.68h), half3(0.13h, 0.62h, 0.72h), half(a)) * half(smoothstep(0.32, 0.85, a));
    half3 aur1 = half3(0.21h, 0.88h, 0.74h) * half(ribbon1 * (1.0 - uv.y));
    half3 aur2 = half3(0.68h, 0.42h, 0.96h) * half(ribbon2 * (1.0 - uv.y));
    half3 e = (neb * 0.52h + aur1 * 0.48h + aur2 * 0.32h) * half(intensity);
    return half4(color.rgb + e, max(color.a, max(e.r, max(e.g, e.b))));
}

/// Daylight volumetric sunbeams & drifting warm motes for Meadow / Cozy Room / Morning / Afternoon stages.
[[ stitchable ]] half4 molibooSunbeams(float2 position, half4 color, float2 size, float time, half4 tint, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float2 origin = float2(0.15, -0.12);
    float2 delta = uv - origin;
    float dist = length(delta);
    float angle = atan2(delta.y, delta.x);
    float rays = 0.5 + 0.5 * sin(angle * 11.0 + time * 0.28) * cos(angle * 7.0 - time * 0.19);
    float shaft = pow(max(0.0, rays), 3.2) * smoothstep(1.25, 0.05, dist) * smoothstep(0.0, 0.35, uv.x + uv.y * 0.5);
    float shimmer = mbNoise(uv * 9.0 + float2(time * 0.18, -time * 0.24));
    half3 beam = tint.rgb * half((shaft * 0.28 + pow(shimmer, 4.0) * 0.08) * intensity);
    return half4(color.rgb + beam, max(color.a, max(beam.r, max(beam.g, beam.b))));
}

/// Soft volumetric stage halo behind the active Moliboo: breathing radial aura + subtle concentric harmonic rings.
[[ stitchable ]] half4 molibooStageAura(float2 position, half4 color, float2 size, float time, half4 tint, float strength) {
    float2 uv = (position / max(size, float2(1.0))) - float2(0.5);
    float d = length(uv) * 2.0;
    if (d > 1.0) return color;
    float breath = 0.88 + 0.12 * sin(time * 2.1);
    float core = exp(-d * d * 3.8) * breath;
    float ring = smoothstep(0.06, 0.0, abs(d - (0.52 + 0.06 * sin(time * 1.4)))) * 0.35;
    float alpha = clamp((core * 0.65 + ring) * strength * (1.0 - d), 0.0, 1.0);
    half3 glow = mix(tint.rgb, half3(1.0h, 0.98h, 0.95h), half(core * 0.35)) * half(alpha);
    return half4(color.rgb + glow, max(color.a, half(alpha)));
}

/// Interactive joy/care pulse wave: expanding chromatic/teal-gold ring triggered on care actions or stage taps.
[[ stitchable ]] half4 molibooJoyPulse(float2 position, half4 color, float2 size, float age, half4 tint) {
    if (age <= 0.0 || age >= 1.4) return color;
    float2 uv = (position / max(size, float2(1.0))) - float2(0.5);
    float d = length(uv) * 2.0;
    // Ring ends at 0.86 of the canvas half-side so it fades out before any edge (never squared off by the bounds).
    float radius = (age / 1.4) * 0.86;
    float fade = clamp(1.0 - age / 1.4, 0.0, 1.0);
    float ring = exp(-pow((d - radius) * 14.0, 2.0)) * fade;
    // Premultiplied "over" composite: additive colour on near-transparent layers (shadows, bubble) showed as
    // bright rectangles; compositing keeps the ring a clean soft circle everywhere.
    half a = half(ring * 0.6);
    half3 pulse = mix(tint.rgb, mbHue(fract(d * 1.5 - age * 0.8)), 0.35h) * a;
    return half4(pulse + color.rgb * (1.0h - a), a + color.a * (1.0h - a));
}

/// Specular liquid-glass rim sheen for pills, cards, and active controls.
[[ stitchable ]] half4 molibooSpecularRim(float2 position, half4 color, float2 size, float time, float strength) {
    if (color.a < 0.01h) return color;
    float2 uv = position / max(size, float2(1.0));
    float2 centered = uv - float2(0.5);
    float edge = smoothstep(0.34, 0.50, max(abs(centered.x), abs(centered.y)));
    float sweep = 0.5 + 0.5 * cos(atan2(centered.y, centered.x) - time * 0.9);
    float glint = pow(sweep, 4.0) * edge * strength;
    half3 c = color.rgb + half3(0.88h, 0.97h, 1.0h) * half(glint * 0.45) * color.a;
    return half4(min(c, half3(color.a)), color.a);
}

/// Tap ripple: radial sine displacement that decays with distance and age (distortion effect).
[[ stitchable ]] float2 molibooRipple(float2 position, float2 origin, float age, float amplitude) {
    float d = distance(position, origin);
    float wave = sin(d * 0.09 - age * 14.0) * exp(-age * 3.0) * exp(-d * 0.012);
    float2 dir = d > 0.0 ? (position - origin) / d : float2(0);
    return position + dir * wave * amplitude * step(0.0, age) * step(age, 1.6);
}

/// Shimmer sweep for Legendary / Epic / Rare cards and badges: a bright diagonal band + secondary prismatic glint.
[[ stitchable ]] half4 molibooShimmer(float2 position, half4 color, float2 size, float time, float strength) {
    if (color.a < 0.01h) return color;
    float2 uv = position / max(size, float2(1.0));
    float x = fract(time / 2.8) * 2.6 - 0.8;
    float band1 = exp(-pow((uv.x + uv.y * 0.6 - x) * 7.0, 2.0));
    float band2 = exp(-pow((uv.x + uv.y * 0.6 - (x - 0.22)) * 14.0, 2.0)) * 0.55;
    half3 c = color.rgb + (half3(1.0h, 0.95h, 0.78h) * half(band1) + half3(0.65h, 0.94h, 1.0h) * half(band2)) * half(strength) * color.a;
    return half4(min(c, half3(color.a)), color.a);
}

/// Pack opening: the foil wrapper burns away from the centre with a glowing edge (layer effect, `progress` 0→1).
[[ stitchable ]] half4 molibooPackReveal(float2 position, SwiftUI::Layer layer, float2 size, float progress) {
    half4 c = layer.sample(position);
    float2 uv = position / max(size, float2(1.0));
    float n = mbFbm(uv * 5.0);
    float d = distance(uv, float2(0.5)) * 1.3 + n * 0.35;
    float edge = progress * 1.7;
    if (d < edge - 0.06) return half4(0);
    float glow = smoothstep(edge + 0.06, edge, d);
    half3 hot = half3(1.0h, 0.82h, 0.42h) * half(glow * 1.45);
    return half4(c.rgb + hot * c.a, c.a);
}
