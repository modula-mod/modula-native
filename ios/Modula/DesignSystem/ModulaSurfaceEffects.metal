#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Surface effects for Settings chrome. Every shader is cheap (no loops, no texture
// reads beyond one layer sample) and is driven from Swift by a paused-capable
// TimelineView, so Reduce Motion freezes them on a static frame.

static inline float modulaHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

/// Diagonal light sweep plus fixed film grain for hero icon tiles.
/// `time` is seconds (wrapped by the caller); `intensity` 0...1.
[[ stitchable ]] half4 modulaHeroSheen(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float intensity
) {
    if (color.a < 0.002) {
        return color;
    }
    float2 uv = position / max(size, float2(1.0));
    float band = uv.x * 0.85 + uv.y * 0.55;
    float phase = fract(time * 0.16) * 2.8 - 0.9;
    float d = band - phase;
    float sheen = exp(-d * d * 70.0) * 0.42 + exp(-d * d * 900.0) * 0.25;
    float grain = (modulaHash(floor(position)) - 0.5) * 0.07;
    float glow = (1.0 - uv.y) * 0.08;
    float lift = (sheen + glow) * intensity + grain * intensity;
    half3 rgb = color.rgb + half3(half(lift)) * color.a;
    rgb = clamp(rgb, half3(0.0), half3(color.a));
    return half4(rgb, color.a);
}

/// Live radar for the service Status page. `energy` scales the sweep and pulse:
/// 1 = operational, ~0.55 = degraded, 0 = outage/unknown (static scope only).
[[ stitchable ]] half4 modulaStatusRadar(
    float2 position,
    half4 color,
    float2 size,
    float time,
    half4 tint,
    float energy
) {
    float radius = max(min(size.x, size.y) * 0.5, 1.0);
    float2 d = position - size * 0.5;
    float r = length(d) / radius;
    if (r > 1.0) {
        return half4(0.0);
    }
    const float tau = 6.28318530718;
    float angle = atan2(d.y, d.x) + 3.14159265359;
    float sweep = fmod(time * 1.35, tau);
    float behind = fmod(sweep - angle + 2.0 * tau, tau);
    float trail = exp(-behind * 2.4) * energy;
    float beam = (1.0 - smoothstep(0.0, 0.035, behind)) * energy;

    float f = fract(r * 4.0);
    float ringDist = min(f, 1.0 - f) * 0.25 * radius;
    float rings = 1.0 - smoothstep(0.0, 1.1, ringDist);

    float crossDist = min(abs(d.x), abs(d.y));
    float crossLines = (1.0 - smoothstep(0.0, 0.9, crossDist)) * (1.0 - r * 0.6);

    float pr = fract(time * 0.42);
    float pulse = (1.0 - smoothstep(0.0, 0.035, abs(r - pr))) * (1.0 - pr) * energy;

    float core = exp(-r * r * 90.0);
    float grain = (modulaHash(floor(position * 0.5)) - 0.5) * 0.04;

    float alpha = 0.20 * rings + 0.12 * crossLines + 0.42 * trail * (1.0 - r * 0.35)
        + 0.55 * beam + 0.65 * pulse + 0.95 * core + grain;
    alpha *= 1.0 - smoothstep(0.94, 1.0, r);
    alpha = clamp(alpha, 0.0, 1.0);
    half a = half(alpha) * tint.a;
    return half4(tint.rgb * a, a);
}

/// Expanding refraction ring from a tap point. `progress` 0...1 drives the ring
/// outwards and fades it; `amplitude` is the maximum sample offset in points.
[[ stitchable ]] half4 modulaTapRipple(
    float2 position,
    SwiftUI::Layer layer,
    float2 origin,
    float2 size,
    float progress,
    float amplitude
) {
    float p = saturate(progress);
    if (p <= 0.0 || p >= 1.0) {
        return layer.sample(position);
    }
    float2 d = position - origin;
    float dist = length(d);
    float reach = length(size) * 0.9;
    float front = p * reach;
    float width = 26.0;
    float x = (dist - front) / width;
    float envelope = exp(-x * x) * (1.0 - p) * (1.0 - p);
    float2 dir = dist > 0.001 ? d / dist : float2(0.0);
    float2 offset = dir * sin(x * 3.2) * amplitude * envelope;
    half4 sampled = layer.sample(position - offset);
    sampled.rgb += half(envelope * 0.10) * sampled.a;
    return sampled;
}
