#include <metal_stdlib>
using namespace metal;

// Spectral Drape: strands of dots on a noise-driven sheet, perspective-projected, additive.
struct DrapeUniforms {
    float4x4 viewProj;
    float time;
    float aspect;
    float pointScale;
    float dark;          // 1 dark, 0 light
    float4 nearColor;    // pale lavender (dark) / accent (light)
    float4 farColor;     // deep purple
    float2 ripple;       // touch point in sheet uv, (-9,-9) = none
    float rippleAge;
    uint strands;
    uint dotsPerStrand;
};

struct DrapeOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

static float3 hash3(float3 p) {
    p = float3(dot(p, float3(127.1, 311.7, 74.7)), dot(p, float3(269.5, 183.3, 246.1)), dot(p, float3(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}

// Gradient noise (simplex-like smoothness, cheap).
static float gnoise(float3 p) {
    float3 i = floor(p), f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float n000 = dot(hash3(i + float3(0,0,0)), f - float3(0,0,0));
    float n100 = dot(hash3(i + float3(1,0,0)), f - float3(1,0,0));
    float n010 = dot(hash3(i + float3(0,1,0)), f - float3(0,1,0));
    float n110 = dot(hash3(i + float3(1,1,0)), f - float3(1,1,0));
    float n001 = dot(hash3(i + float3(0,0,1)), f - float3(0,0,1));
    float n101 = dot(hash3(i + float3(1,0,1)), f - float3(1,0,1));
    float n011 = dot(hash3(i + float3(0,1,1)), f - float3(0,1,1));
    float n111 = dot(hash3(i + float3(1,1,1)), f - float3(1,1,1));
    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

vertex DrapeOut spectralDrapeVertex(uint vid [[vertex_id]], constant DrapeUniforms &U [[buffer(0)]]) {
    uint s = vid / U.dotsPerStrand, d = vid % U.dotsPerStrand;
    float2 uv = float2(float(s) / float(U.strands - 1), float(d) / float(U.dotsPerStrand - 1));
    float2 xz = (uv - 0.5) * float2(6.0, 6.0);
    float t = U.time * 0.12;
    // Domain-warped (curl-ish) noise: deep billowing folds.
    float3 q = float3(xz * 0.35, t);
    float2 warp = float2(gnoise(q + float3(3.1, 0, 0)), gnoise(q + float3(0, 7.7, 0)));
    float h = gnoise(float3(xz * 0.45 + warp * 1.6, t * 1.3)) * 1.6
            + gnoise(float3(xz * 0.9 + warp, t * 1.7 + 5.0)) * 0.5;
    float3 pos = float3(xz.x + warp.x * 0.6, h, xz.y + warp.y * 0.3);
    if (U.ripple.x > -8.0) {
        float r = distance(uv, U.ripple);
        float w = U.rippleAge * 0.6;
        pos.y += 0.35 * exp(-U.rippleAge * 1.5) * sin((r - w) * 40.0) * exp(-abs(r - w) * 12.0);
    }
    float4 clip = U.viewProj * float4(pos, 1.0);
    DrapeOut o;
    o.position = clip;
    float depth = clamp((clip.w - 3.0) / 7.0, 0.0, 1.0);   // 0 near → 1 far
    float lift = clamp(h * 0.35 + 0.5, 0.0, 1.0);          // folds catching light
    float bright = (1.0 - depth) * (0.45 + 0.55 * lift);
    float3 c = mix(U.farColor.rgb, U.nearColor.rgb, bright);
    float fade = (1.0 - depth * depth);
    o.color = float4(c * fade, fade * (0.25 + 0.75 * bright));
    o.pointSize = U.pointScale * (1.0 + 2.2 * bright * bright) / max(clip.w, 0.5) * 6.0;
    return o;
}

fragment float4 spectralDrapeFragment(DrapeOut in [[stage_in]], float2 pc [[point_coord]], constant DrapeUniforms &U [[buffer(0)]]) {
    float r = length(pc - 0.5) * 2.0;
    float core = smoothstep(1.0, 0.35, r);
    float glow = exp(-r * r * 3.0) * 0.5;     // soft bloom halo
    float a = (core + glow) * in.color.a;
    if (U.dark > 0.5) {
        return float4(in.color.rgb * a, a);    // additive (dark)
    }
    return float4(in.color.rgb * a, a);        // premultiplied over (light)
}
