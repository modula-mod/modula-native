#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Modula Effect Kit shaders. Each is a single-pass colour/layer effect with no
// loops and at most one layer sample, so they stay well inside a 120 Hz frame
// budget. Time is wrapped by the caller (ModulaSurfaceClock) to keep Float precision.

static inline float fxHash(float2 p) {
    p = fract(p * float2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

static inline float fxBlob(float2 uv, float2 centre, float radius) {
    float2 d = uv - centre;
    return exp(-dot(d, d) / (radius * radius));
}

/// Animated aurora / mesh gradient tinted from two colours over a dark or light base.
/// `intensity` 0...1 scales the colour lift; `time` in seconds.
[[ stitchable ]] half4 modulaAurora(
    float2 position,
    half4 color,
    float2 size,
    float time,
    half4 tintA,
    half4 tintB,
    half4 base,
    float intensity
) {
    float2 uv = position / max(size, float2(1.0));
    float aspect = size.x / max(size.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float t = time * 0.22;

    float2 c1 = float2((0.25 + 0.18 * sin(t * 1.10)) * aspect, 0.30 + 0.16 * cos(t * 0.90));
    float2 c2 = float2((0.78 + 0.16 * cos(t * 0.80)) * aspect, 0.42 + 0.20 * sin(t * 1.30));
    float2 c3 = float2((0.50 + 0.26 * sin(t * 0.60 + 1.7)) * aspect, 0.88 + 0.10 * cos(t * 1.70));
    float2 c4 = float2((0.12 + 0.10 * cos(t * 1.40 + 0.6)) * aspect, 0.78 + 0.12 * sin(t * 0.70));

    float b1 = fxBlob(p, c1, 0.42);
    float b2 = fxBlob(p, c2, 0.38);
    float b3 = fxBlob(p, c3, 0.46);
    float b4 = fxBlob(p, c4, 0.30);

    // Curtain ribbons: soft vertical bands that drift sideways like aurora.
    float ribbon = sin(p.x * 5.2 + t * 2.2 + sin(p.y * 3.1 - t) * 1.4) * 0.5 + 0.5;
    ribbon *= smoothstep(0.95, 0.15, uv.y) * 0.35;

    half3 rgb = base.rgb;
    rgb = mix(rgb, tintA.rgb, half(saturate(b1 * 0.85 + ribbon * 0.6) * intensity));
    rgb = mix(rgb, tintB.rgb, half(saturate(b2 * 0.75) * intensity));
    rgb = mix(rgb, mix(tintA.rgb, tintB.rgb, 0.5h), half(saturate(b3 * 0.55) * intensity));
    rgb += half3(tintB.rgb) * half(b4 * 0.18 * intensity);

    float grain = (fxHash(floor(position)) - 0.5) * 0.035;
    rgb += half3(half(grain));
    return half4(clamp(rgb, half3(0.0), half3(1.0)), 1.0h);
}

/// Skeleton shimmer: a soft diagonal highlight band sweeping across opaque pixels.
[[ stitchable ]] half4 modulaShimmer(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float strength
) {
    if (color.a < 0.002) {
        return color;
    }
    float span = size.x + size.y;
    float phase = fract(time * 0.55) * (span * 1.6) - span * 0.3;
    float d = (position.x + position.y * 0.35) - phase;
    float band = exp(-(d * d) / (span * span * 0.004));
    half lift = half(band * strength) * color.a;
    return half4(min(color.rgb + lift, half3(color.a)), color.a);
}

/// Specular highlight at a normalised point (0...1) — used by card tilt so the
/// light follows the finger / the card's tilt direction.
[[ stitchable ]] half4 modulaSpecular(
    float2 position,
    half4 color,
    float2 size,
    float2 light,
    float strength
) {
    if (color.a < 0.002 || strength <= 0.0) {
        return color;
    }
    float2 uv = position / max(size, float2(1.0));
    float2 d = uv - light;
    float spot = exp(-dot(d, d) * 7.0) * 0.22 + exp(-dot(d, d) * 60.0) * 0.12;
    half lift = half(spot * strength) * color.a;
    return half4(min(color.rgb + lift, half3(color.a)), color.a);
}
