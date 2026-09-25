#import <Foundation/Foundation.h>
#import <simd/simd.h>

// ============================================================
// Camera System
//
// Manages view + projection matrices for 3D rendering.
//
// COORDINATE CONVENTION: LEFT-HANDED, Direct3D style — the game's .x models
// and level files are authored for D3D (x right, y up, z into the screen,
// clockwise = front face). Metal's clip space matches D3D (z in [0,1]), so
// using left-handed look-at / perspective (D3DXMatrix*LH equivalents) means
// the data can be used unmodified: no mirroring, no winding flip, no UV flip.
// The default camera sits at -z looking towards +z, which is where the
// original game models face (verified: Santa's front faces -z).
// ============================================================

@interface Camera : NSObject

// Position and orientation
@property (nonatomic) simd_float3 position;
@property (nonatomic) simd_float3 target;
@property (nonatomic) simd_float3 up;

// Projection parameters
@property (nonatomic) float fov;         // vertical FOV, radians (default 45°)
@property (nonatomic) float nearPlane;   // default 0.1
@property (nonatomic) float farPlane;    // default 100.0
@property (nonatomic) float aspectRatio; // width/height

// Matrices (recomputed on demand)
- (simd_float4x4)viewMatrix;
- (simd_float4x4)projectionMatrix;
- (simd_float4x4)viewProjectionMatrix;

// Convenience: update aspect on drawable size change
- (void)setViewportSize:(CGSize)size;

@end
