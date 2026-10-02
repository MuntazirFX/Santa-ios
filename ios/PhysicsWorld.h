#import <Foundation/Foundation.h>
#import <simd/simd.h>

// ============================================================
// Physics World
//
// Footprint-based ground/collision against the current level's
// walkable entities (PLATTFORM/RECTFORM/EXIT/ELEVATOR/MOVER/JUMPER)
// and hazard entities (ENEMY/ELEVATORENEMY), resolved via
// data/elements.txt (ElementCatalog) exactly as verified in
// tools/test_physics.cpp.
//
// Current status: IMPLEMENTED (circular footprint query)
// ============================================================

@interface PhysicsWorld : NSObject

// Fallback ground level, used only if no footprint covers a query point.
@property (nonatomic) float groundY;

// Loads footprints for one level file from the given XPK, via
// AssetManager + LevelParser + ElementCatalog (same data path as
// GameEngine). Call once after picking a level; returns NO if the
// xpk/level/catalog can't be read.
- (BOOL)loadLevelFootprints:(NSString *)levelPath fromXPK:(NSString *)xpkPath;

// Highest walkable footprint's y under (x,z); falls back to groundY
// if nothing covers that point.
- (float)groundHeightAtX:(float)x z:(float)z;

// YES if (x,z) falls inside a hazard (ENEMY/ELEVATORENEMY) footprint,
// independent of height — caller should compare y separately.
- (BOOL)checkCollisionAtPosition:(simd_float3)position radius:(float)radius;

@end
