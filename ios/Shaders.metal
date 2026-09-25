#include <metal_stdlib>
using namespace metal;

// ------------------------------------------------------------------
// Direct3D -> Metal notes
//  * Clip space: D3D and Metal both use z in [0,1] (OpenGL uses [-1,1]).
//    The old mesh shader wrote the model position straight to clip space,
//    so every vertex with z < 0 was clipped away (half the model, always).
//    Vertices now go through a real left-handed MVP matrix (Camera.mm).
//  * Texture space: D3D and Metal both have V = 0 at the TOP. UVs from the
//    .x files are used unchanged (no "1 - v").
// ------------------------------------------------------------------

struct MeshUniforms {
    float4x4 mvp;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float3 color;
};

// Vertex layout in buffer(0): 8 floats per vertex = pos(3) uv(2) color(3)
vertex VertexOut mesh_vertex(const device float *data [[buffer(0)]],
                             constant MeshUniforms &u [[buffer(1)]],
                             uint vid [[vertex_id]]) {
    uint base = vid * 8;
    float4 pos = float4(data[base], data[base + 1], data[base + 2], 1.0);

    VertexOut out;
    out.position = u.mvp * pos;
    out.uv = float2(data[base + 3], data[base + 4]);
    out.color = float3(data[base + 5], data[base + 6], data[base + 7]);
    return out;
}

fragment float4 mesh_fragment(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              sampler samp [[sampler(0)]]) {
    float4 texColor = tex.sample(samp, in.uv);
    // Cut-out textures (e.g. #tanne.dds is ARGB1555) — alpha test like D3D's ALPHAREF.
    if (texColor.a < 0.5) {
        discard_fragment();
    }
    return float4(texColor.rgb * in.color, 1.0);
}

// ------------------------------------------------------------------
// 2D sprites / text.  Vertex layout in buffer(0): float4 = (ndcX, ndcY, u, v)
// (required by MetalView.mm — these two functions were missing before,
//  which left the sprite pipeline nil.)
// ------------------------------------------------------------------
struct SpriteOut {
    float4 position [[position]];
    float2 uv;
};

vertex SpriteOut sprite_vertex(const device float4 *verts [[buffer(0)]],
                               uint vid [[vertex_id]]) {
    float4 v = verts[vid];
    SpriteOut out;
    out.position = float4(v.xy, 0.0, 1.0);
    out.uv = v.zw;
    return out;
}

fragment float4 sprite_fragment(SpriteOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                sampler samp [[sampler(0)]]) {
    return tex.sample(samp, in.uv);
}

// ------------------------------------------------------------------
// Level rendering (LevelRenderer.mm)
//   buffer(0): 8 floats per vertex (pos3 uv2 color3), raw model space
//   buffer(1): view * projection (left-handed, depth [0,1])
//   buffer(2): per-instance model matrix (translate * rotateY * scale)
// The models ship without normals, so lighting uses the flat face normal
// derived from screen-space derivatives. abs() makes it winding independent.
// ------------------------------------------------------------------
struct LevelOut {
    float4 position [[position]];
    float2 uv;
    float3 worldPos;
};

vertex LevelOut level_vertex(const device float *data [[buffer(0)]],
                             constant float4x4 &viewProj [[buffer(1)]],
                             constant float4x4 &model [[buffer(2)]],
                             uint vid [[vertex_id]]) {
    uint base = vid * 8;
    float4 wp = model * float4(data[base], data[base + 1], data[base + 2], 1.0);

    LevelOut out;
    out.position = viewProj * wp;
    out.uv = float2(data[base + 3], data[base + 4]);
    out.worldPos = wp.xyz;
    return out;
}

fragment float4 level_fragment(LevelOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler samp [[sampler(0)]]) {
    // derivatives first (before any discard)
    float3 nRaw = cross(dfdx(in.worldPos), dfdy(in.worldPos));
    float nLen = length(nRaw);
    float3 n = (nLen > 1e-8) ? (nRaw / nLen) : float3(0.0, 1.0, 0.0);

    float4 c = tex.sample(samp, in.uv);
    if (c.a < 0.5) {
        discard_fragment();
    }

    float3 L = normalize(float3(0.35, 0.85, -0.40));
    float light = 0.45 + 0.55 * abs(dot(n, L));
    return float4(c.rgb * light, 1.0);
}
