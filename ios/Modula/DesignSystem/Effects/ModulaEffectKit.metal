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
    half3 a = min(tintA.rgb * 1.15h, half3(1.0));
    half3 b = min(tintB.rgb * 1.10h, half3(1.0));
    rgb = mix(rgb, a, half(saturate(b1 * 0.95 + ribbon * 0.7) * intensity));
    rgb = mix(rgb, b, half(saturate(b2 * 0.85) * intensity));
    rgb = mix(rgb, mix(a, b, 0.5h), half(saturate(b3 * 0.6) * intensity));
    rgb += b * half(b4 * 0.22 * intensity);

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

// MARK: - Lock screen shaders (App Lock: passcode / pattern / Orbit)
// All single-pass, no loops (except the fixed 3-octave noise), at most 3 layer samples.

static inline float lockNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = fxHash(i), b = fxHash(i + float2(1, 0)), c = fxHash(i + float2(0, 1)), d = fxHash(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float lockFbm(float2 p) {
    float v = 0.0, a = 0.5;
    v += a * lockNoise(p); p *= 2.02; a *= 0.5;
    v += a * lockNoise(p); p *= 2.03; a *= 0.5;
    v += a * lockNoise(p);
    return v;
}

/// Soft aurora: domain-warped noise mixed between three brand hues. `dark` 0/1.
[[ stitchable ]] half4 lockAurora(float2 pos, half4 color, float2 size, float time, float dark) {
    float2 uv = pos / max(size, float2(1));
    float2 q = uv * float2(2.2, 3.0);
    float w = lockFbm(q + float2(time * 0.03, -time * 0.02));
    float n = lockFbm(q + w * 1.6 + float2(-time * 0.025, time * 0.04));
    half3 c1 = half3(0.36, 0.27, 0.95), c2 = half3(0.10, 0.66, 0.92), c3 = half3(0.86, 0.32, 0.74);
    half3 tint = mix(mix(c1, c2, half(smoothstep(0.25, 0.65, n))), c3, half(smoothstep(0.6, 0.9, w)));
    half3 base = dark > 0.5 ? half3(0.03, 0.03, 0.06) : half3(0.97, 0.97, 0.99);
    half amount = dark > 0.5 ? 0.42 : 0.22;
    half fade = half(mix(1.0, 0.55, uv.y));
    return half4(mix(base, tint, amount * fade), 1.0);
}

/// Press shimmer inside a key: a caustic sweep plus a soft spot at the touch, already clipped by the caller.
[[ stitchable ]] half4 lockKeyCaustic(float2 pos, half4 color, float2 size, float t, float dark) {
    if (color.a <= 0.0) return color;
    float2 uv = pos / max(size, float2(1));
    float c = lockNoise(uv * 5.0 + float2(t * 2.0, -t * 1.4));
    float band = smoothstep(0.55, 0.95, c) * (1.0 - smoothstep(0.0, 1.0, t));
    float spot = (1.0 - smoothstep(0.0, 0.55, distance(uv, float2(0.5)))) * (1.0 - t);
    half k = half(clamp(band * 0.55 + spot * 0.35, 0.0, 1.0));
    half3 glow = dark > 0.5 ? half3(1.0) : half3(0.35, 0.55, 0.75);
    return half4(glow * k, k) * color.a;
}

/// One-shot ripple distortion radiating from `origin`. t: 0→1 over the ripple.
[[ stitchable ]] float2 lockRipple(float2 pos, float2 origin, float t, float amplitude) {
    float d = distance(pos, origin);
    float front = t * 520.0;
    float ring = exp(-pow((d - front) / 36.0, 2.0));
    float2 dir = d > 0.001 ? (pos - origin) / d : float2(0);
    return pos + dir * sin((d - front) * 0.12) * amplitude * ring * (1.0 - t);
}

/// Noise dissolve with a glowing edge. progress 0 = intact, 1 = gone.
[[ stitchable ]] half4 lockDissolve(float2 pos, half4 color, float2 size, float progress) {
    float n = lockFbm(pos / 38.0);
    float edge = progress * 1.15 - 0.075;
    if (n < edge) return half4(0);
    float glow = 1.0 - smoothstep(0.0, 0.08, n - edge);
    half3 rim = half3(0.55, 0.85, 1.0);
    return half4(mix(color.rgb, rim * color.a, half(glow * step(0.001, progress))), color.a);
}

/// Chromatic split for wrong-code shake. amount in points (0 = off).
[[ stitchable ]] half4 lockChromatic(float2 pos, SwiftUI::Layer layer, float amount) {
    half4 base = layer.sample(pos);
    if (amount <= 0.01) return base;
    half4 r = layer.sample(pos + float2(amount, 0));
    half4 b = layer.sample(pos - float2(amount, 0));
    return half4(r.r, base.g, b.b, max(base.a, max(r.a, b.a)));
}

/// Send-to-island edge glow: iridescent (blue/purple/green/pink) band hugging a rounded
/// card's edge, with drifting sparkles. `intensity` 0…1 grows as the card rises.
[[ stitchable ]] half4 islandSendGlow(float2 pos, half4 color, float2 size, float time, float intensity, float radius) {
    float2 h = size * 0.5;
    float2 q = abs(pos - h) - (h - radius);
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius; // <0 inside
    float edge = exp(-pow(d / (3.0 + 7.0 * intensity), 2.0));
    float ang = atan2(pos.y - h.y, pos.x - h.x) + time * 2.2;
    half3 a = half3(0.25, 0.55, 1.0), b = half3(0.65, 0.35, 1.0), c = half3(0.3, 0.95, 0.6), e = half3(1.0, 0.4, 0.75);
    float s = 0.5 + 0.5 * sin(ang * 2.0);
    float t2 = 0.5 + 0.5 * sin(ang * 3.0 + 1.7);
    half3 hue = mix(mix(a, b, half(s)), mix(c, e, half(s)), half(t2));
    float2 cell = floor(pos / 9.0);
    float rnd = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
    float tw = step(0.93, rnd) * (0.5 + 0.5 * sin(time * 9.0 + rnd * 40.0));
    float sparkle = tw * exp(-pow(d / 14.0, 2.0)) * intensity;
    float k = clamp(edge * (0.35 + 0.65 * intensity) + sparkle, 0.0, 1.0);
    return half4(hue * half(k) + half3(sparkle), half(k));
}
