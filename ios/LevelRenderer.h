#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#import <simd/simd.h>

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

- (instancetype)initWithDevice:(id<MTLDevice>)device
                   colorFormat:(MTLPixelFormat)colorFormat
                   depthFormat:(MTLPixelFormat)depthFormat;

// levelPath e.g. @"levels\\000.dat". Returns NO if nothing could be loaded.
- (BOOL)loadLevel:(NSString *)levelPath;

// Encodes all draw calls. Sets its own pipeline / cull / winding state.
- (void)encodeInto:(id<MTLRenderCommandEncoder>)encoder
        depthState:(id<MTLDepthStencilState>)depthState
      viewportSize:(CGSize)size;

// The player character mesh (e.g. "gfx\\weihnachtsman_000.x"), drawn on top
// of the static level batches each frame at `characterTransform`. Loads and
// caches once; safe to call again with the same file. NOTE: Santa isn't a
// data\elements.txt catalog entry (he's spawned by game code, not placed
// like level objects), so there's no authored SCALING value for him — the
// scale baked into `characterTransform` by the caller is a visual estimate,
// not a verified constant like the level objects' own SCALING values are.
- (BOOL)loadCharacterMesh:(NSString *)file;
@property (nonatomic) BOOL hasCharacter;         // YES once loadCharacterMesh: succeeds and the caller wants it drawn
@property (nonatomic) simd_float4x4 characterTransform;  // column-major model matrix, set every frame by the caller

// Camera control (called from gesture recognizers)
- (void)panByPixels:(CGPoint)delta viewHeight:(CGFloat)viewHeight;   // one finger drag
- (void)zoomByScale:(CGFloat)scale;                                   // pinch (incremental)
- (void)rotateByRadians:(CGFloat)radians;                             // two finger rotate (incremental)
- (void)tiltByRadians:(CGFloat)radians;                               // two finger drag up/down: camera pitch (incremental)

@end
