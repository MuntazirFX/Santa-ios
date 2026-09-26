#import <Foundation/Foundation.h>
#import <simd/simd.h>

// ============================================================
// Physics World
//
// Real ground/collision detection against the level's own platform
// objects (loaded from levels\NNN.dat, resolved via data/elements.txt).
//
// Convention (matches LevelRenderer.mm exactly, so a platform that
// renders at a given spot collides at that same spot):
//   * data/elements.txt RADIUS is the model's footprint radius; SCALING
//     >= 1 is a PERCENT (divide by 100), < 1 is used as-is.
//   * a platform's own y (from the level file) is its walkable surface
//     height — the same value LevelRenderer.mm uses to place Santa's
//     feet at the spawn point.
//   * footprint is treated as a circle of that scaled radius. The game
//     data only ever gives one RADIUS number per element (no separate
//     width/depth), so this is what the data itself supports — not an
//     approximation of some other shape.
// ============================================================

// One walkable surface, already resolved to world space + real radius.
typedef struct {
    float x, y, z;
    float radius;
    BOOL isHazard;   // ENEMY / ELEVATORENEMY — touching this can hurt Santa
} PhysicsFootprint;

@class LevelObject;

@interface PhysicsWorld : NSObject

// Default ground level, used only until a level's platforms are loaded
// (or as a floor-of-last-resort so Santa can never fall through the
// world if he ends up outside every platform's footprint).
@property (nonatomic) float groundY;

// Build the collision world from a level's objects. Call this once right
// after LevelRenderer/GameEngine load a level (same object list they use
// to place the visuals, so collision and rendering never disagree).
- (void)buildFromLevelObjects:(NSArray<LevelObject *> *)objects;

// Highest walkable surface directly under (x,z), or groundY if nothing
// is under that point.
- (float)groundHeightAtX:(float)x z:(float)z;

// YES if (x,z) at the given radius overlaps a hazard object (enemy).
- (BOOL)checkCollisionAtPosition:(simd_float3)position radius:(float)radius;

@end

