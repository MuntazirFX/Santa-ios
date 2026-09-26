#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#import <simd/simd.h>

@class LevelObject;

// ============================================================
// LevelRenderer — draws a whole level (levels\NNN.dat) with Metal.
//
// Data path (all verified on the real archive):
//   levels\000.dat  ->  [GameEngine parseLevelData:]  (name, x, y, z, variant)
//   data\elements.txt -> ElementCatalog                (.x model, SCALING, TYPE)
//   gfx\*.x + maps\*.dds/.tga -> one GPU mesh + texture per unique model
//
// Conventions (see README "Direct3D -> Metal notes"):
//   * world units: the level grid is 3.0 units; x/z is the ground plane, y is up
//   * SCALING in elements.txt: values >= 1 are PERCENT (7.51 -> 0.0751, so a
//     40-unit platform model becomes exactly one 3.0 grid cell); values < 1
//     (troll 0.014, raven 0.1, savepoint 0.03) are used as-is
//   * 'variant' is the rotation about Y in 90 degree steps (verified on the
//     straight/corner pieces of level 000: 4 outer walls map 0,1,2,3 in order)
//   * left-handed, clockwise-front, back-face culling — same as the D3D data
// ============================================================
@interface LevelRenderer : NSObject

@property (nonatomic, readonly) BOOL hasLevel;
@property (nonatomic, readonly) NSUInteger objectCount;   // objects placed on screen
@property (nonatomic, readonly) NSString *summary;        // human readable load report

// The raw placed-object list from levels\NNN.dat (name + world position +
// resolved element type), for anything that needs the level's own data —
// PhysicsWorld builds its collision footprints straight from this so
// collision can never disagree with what's on screen.
@property (nonatomic, readonly) NSArray<LevelObject *> *objects;
// Where Santa starts: the first placed object's position (same point this
// renderer already stands the static bind-pose Santa on).
@property (nonatomic, readonly) simd_float3 spawnPoint;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                   colorFormat:(MTLPixelFormat)colorFormat
                   depthFormat:(MTLPixelFormat)depthFormat;

// levelPath e.g. @"levels\\000.dat". Returns NO if nothing could be loaded.
- (BOOL)loadLevel:(NSString *)levelPath;

// Encodes all draw calls. Sets its own pipeline / cull / winding state.
- (void)encodeInto:(id<MTLRenderCommandEncoder>)encoder
        depthState:(id<MTLDepthStencilState>)depthState
      viewportSize:(CGSize)size;

// Camera control (called from gesture recognizers)
- (void)panByPixels:(CGPoint)delta viewHeight:(CGFloat)viewHeight;   // one finger drag
- (void)zoomByScale:(CGFloat)scale;                                   // pinch (incremental)
- (void)rotateByRadians:(CGFloat)radians;                             // two finger rotate (incremental)
- (void)tiltByRadians:(CGFloat)radians;                               // two finger drag up/down: camera pitch (incremental)

// ---------- live Santa (Play mode) ----------
// Overwrites the live Santa batch's transform (the same GPU mesh already
// used for the static bind-pose display — this just makes its position
// dynamic instead of fixed at the spawn point). facingAngle: radians about
// Y, 0 = +Z, matching CharacterController.facingAngle / LevelModelMatrix.
- (void)setSantaPosition:(simd_float3)position facingAngle:(float)facingAngle;

// Lets Play mode drive the look-at point directly (character following)
// instead of finger-pan. Zoom/rotate/tilt keep working normally on top of
// whatever target is set here.
- (void)setCameraTarget:(simd_float3)target;

@end
