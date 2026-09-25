#import "Camera.h"

@implementation Camera

- (instancetype)init {
    self = [super init];
    if (self) {
        _position = simd_make_float3(0, 0, -3);   // D3D: look along +z
        _target = simd_make_float3(0, 0, 0);
        _up = simd_make_float3(0, 1, 0);
        
        _fov = 45.0f * (M_PI / 180.0f);
        _nearPlane = 0.1f;
        _farPlane = 100.0f;
        _aspectRatio = 1.0f;
    }
    return self;
}

- (void)setViewportSize:(CGSize)size {
    if (size.height > 0) {
        _aspectRatio = (float)(size.width / size.height);
    }
}

- (simd_float4x4)viewMatrix {
    // Left-handed look-at (== D3DXMatrixLookAtLH, written for column vectors).
    simd_float3 z = simd_normalize(_target - _position);   // forward
    simd_float3 x = simd_normalize(simd_cross(_up, z));    // right
    simd_float3 y = simd_cross(z, x);                      // up

    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[0] = simd_make_float4(x.x, y.x, z.x, 0);
    m.columns[1] = simd_make_float4(x.y, y.y, z.y, 0);
    m.columns[2] = simd_make_float4(x.z, y.z, z.z, 0);
    m.columns[3] = simd_make_float4(-simd_dot(x, _position),
                                    -simd_dot(y, _position),
                                    -simd_dot(z, _position),
                                    1.0f);
    return m;
}

- (simd_float4x4)projectionMatrix {
    // Left-handed perspective, depth range [0,1] (== D3DXMatrixPerspectiveFovLH).
    // This is exactly what Metal expects — the previous version used the
    // OpenGL [-1,1] depth mapping, which puts everything nearer than the
    // midpoint of the frustum in the wrong place and clips it incorrectly.
    float yScale = 1.0f / tanf(_fov * 0.5f);
    float xScale = yScale / _aspectRatio;
    float zRange = _farPlane - _nearPlane;

    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[0] = simd_make_float4(xScale, 0, 0, 0);
    m.columns[1] = simd_make_float4(0, yScale, 0, 0);
    m.columns[2] = simd_make_float4(0, 0, _farPlane / zRange, 1.0f);
    m.columns[3] = simd_make_float4(0, 0, -(_nearPlane * _farPlane) / zRange, 0);
    return m;
}

- (simd_float4x4)viewProjectionMatrix {
    return simd_mul([self projectionMatrix], [self viewMatrix]);
}

@end
