#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Inverse texture mapping: every radius rotates by a different amount.
// SwiftUI::Layer supplies premultiplied color, so the fade scales RGBA together.
[[ stitchable ]] half4 seruSpiralCollapse(float2 position, SwiftUI::Layer layer,
                                         float2 size, float progress, float strength) {
    float p = clamp(progress, 0.0f, 1.0f);
    if (p <= 0.0f) return layer.sample(position);
    if (p >= 1.0f) return half4(0.0h);
    float2 center = size * 0.5f;
    // Keep the greeting silhouette legible, then draw it into the point late.
    float shrink = max(0.002f, 1.0f - pow(p, 2.4f));
    float2 sourceOffset = (position - center) / shrink;
    float radius = length(sourceOffset) / max(1.0f, min(size.x, size.y) * 0.5f);
    float angle = strength * p * p * (0.12f + 0.88f * exp(-1.8f * radius * radius));
    float s = sin(angle), c = cos(angle);
    float2 source = center + float2(c * sourceOffset.x - s * sourceOffset.y,
                                    s * sourceOffset.x + c * sourceOffset.y);
    if (any(source < float2(0.0f)) || any(source > size)) return half4(0.0h);
    return layer.sample(source) * half(1.0f - smoothstep(0.92f, 1.0f, p));
}
