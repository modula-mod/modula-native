#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

static inline float2 modulaPullWarp(float2 uv, float eased, float direction, float warpScale) {
    float top = 1.0 - smoothstep(0.0, 0.80, uv.y);
    float envelope = top * eased * warpScale;
    float ripple = sin(uv.y * 3.14159265 * 1.55) * 0.42;
    float2 fromTopCenter = uv - float2(0.5, 0.0);
    return float2(
        direction * 24.0 * envelope * (0.62 + 0.38 * (1.0 - uv.y)) + fromTopCenter.x * -9.0 * envelope,
        -36.0 * envelope * (0.80 + 0.20 * ripple)
    );
}

[[ stitchable ]] float2 modulaPullRipple(
    float2 position,
    float4 bounds,
    float progress,
    float direction,
    float warpScale
) {
    float2 size = max(bounds.zw, float2(1.0));
    float2 uv = (position - bounds.xy) / size;
    float p = saturate(progress);
    float eased = p * p * (3.0 - 2.0 * p);
    return position + modulaPullWarp(uv, eased, direction, warpScale);
}

[[ stitchable ]] half4 modulaPullLens(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds,
    float progress,
    float direction,
    float warpScale,
    float blurAmount
) {
    float2 size = max(bounds.zw, float2(1.0));
    float2 uv = (position - bounds.xy) / size;
    float p = saturate(progress);
    float eased = p * p * (3.0 - 2.0 * p);
    float2 samplePos = position + modulaPullWarp(uv, eased, direction, warpScale);

    if (eased < 0.012) {
        return layer.sample(position);
    }

    if (blurAmount < 0.5) {
        return layer.sample(samplePos);
    }

    float top = 1.0 - smoothstep(0.0, 0.86, uv.y);
    float radius = mix(0.0, 14.0, eased * (0.42 + 0.58 * top));
    half4 center = layer.sample(samplePos);
    if (radius < 0.35) {
        return center;
    }

    float2 r1 = float2(radius * 0.52);
    float2 r2 = float2(radius);
    half4 acc = center * 0.20;
    acc += layer.sample(samplePos + float2( 1.00,  0.00) * r1) * 0.075;
    acc += layer.sample(samplePos + float2( 0.50,  0.87) * r1) * 0.075;
    acc += layer.sample(samplePos + float2(-0.50,  0.87) * r1) * 0.075;
    acc += layer.sample(samplePos + float2(-1.00,  0.00) * r1) * 0.075;
    acc += layer.sample(samplePos + float2(-0.50, -0.87) * r1) * 0.075;
    acc += layer.sample(samplePos + float2( 0.50, -0.87) * r1) * 0.075;
    acc += layer.sample(samplePos + float2( 0.87,  0.50) * r2) * 0.046;
    acc += layer.sample(samplePos + float2( 0.00,  1.00) * r2) * 0.046;
    acc += layer.sample(samplePos + float2(-0.87,  0.50) * r2) * 0.046;
    acc += layer.sample(samplePos + float2(-0.87, -0.50) * r2) * 0.046;
    acc += layer.sample(samplePos + float2( 0.00, -1.00) * r2) * 0.046;
    acc += layer.sample(samplePos + float2( 0.87, -0.50) * r2) * 0.046;

    half3 rgb = acc.rgb;
    half luma = dot(rgb, half3(0.2126, 0.7152, 0.0722));
    rgb = mix(rgb, half3(luma), half(0.07 * eased));
    rgb += half(0.028 * eased * top);
    return half4(rgb, acc.a);
}
