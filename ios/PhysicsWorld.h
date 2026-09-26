#import <Foundation/Foundation.h>
#import <simd/simd.h>

@class LevelEntity;
@class LevelObject; // from GameEngine.h — the level type the working level viewer actually uses

// ============================================================
// Physics World
//
// Collision against the level's own object list (from LevelLoader),
// using the same per-object RADIUS the original exe's elements.txt
// catalog defines (verified against SantaClausInTrouble.exe's string
// table: ELEMENT/FILE/RADIUS/SCALING/SPEED/... keyword list, and
// against data/elements.txt itself).
//
// Two kinds of check, matching how the catalog's TYPE values split:
//  - "solid ground" types (PLATTFORM, RECTFORM) are used for the
//    downward ground-height raycast a character stands on.
//  - "actor" types (ENEMY, ELEVATORENEMY) are used for circle-vs-circle
//    collision against the character's own radius.
// Both are grid-object approximations (circle/column footprint from
// RADIUS, or a default half-grid-cell footprint of 1.5 world units
// when a catalog entry has no RADIUS), not exact mesh collision —
// good enough to stand on platforms and take enemy hits; swap in
// real per-mesh AABBs later if more precision is needed.
// ============================================================

@interface PhysicsWorld : NSObject

@property (nonatomic) float groundY;          // fallback ground plane, used if no platform is under the point
@property (nonatomic) float platformThickness; // how far below its authored Y a platform's top still counts as "on" it

// Give the physics world the current level's object list (call this
// once after LevelLoader's loadLevel: succeeds, e.g.
// `[physicsWorld setEntities:levelLoader.entities];`).
- (void)setEntities:(NSArray<LevelEntity *> *)entities;

// Same idea, but for LevelObject (GameEngine.h / MetalView's own working
// level parser — data\NNN.dat + elements.txt, already verified byte-exact).
// This is the one to use today; LevelLoader/LevelEntity above is a separate,
// not-yet-wired-in level representation.
- (void)setEntitiesFromLevelObjects:(NSArray<LevelObject *> *)objects;

// Check if a circle of the given radius at `position` overlaps any
// ENEMY / ELEVATORENEMY entity's own radius. Vertical band-limited so
// enemies on a different platform don't collide through the level.
- (BOOL)checkCollisionAtPosition:(simd_float3)position radius:(float)radius;

// Same idea, but returns the colliding entity (or nil) so the caller
// can tell what was hit.
- (LevelEntity *)collidingEntityAtPosition:(simd_float3)position radius:(float)radius;

// Highest PLATTFORM/RECTFORM top surface whose XZ footprint contains
// (x, z), or groundY if nothing is under the point.
- (float)groundHeightAtX:(float)x z:(float)z;

@end
