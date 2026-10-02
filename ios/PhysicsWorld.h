#import <Foundation/Foundation.h>
#import <simd/simd.h>

// ============================================================
// Physics World
//
// Simple collision detection between character and level entities.
//
// Current status: SKELETON
// - Ground plane at y=0
// - AABB collision for level entities (TODO)
// ============================================================

@interface PhysicsWorld : NSObject

// Default ground level
@property (nonatomic) float groundY;

// Check if a point collides with any entity in the level
// (stub for now — always returns NO)
- (BOOL)checkCollisionAtPosition:(simd_float3)position radius:(float)radius;

// Raycast downward to find ground height
- (float)groundHeightAtX:(float)x z:(float)z;

@end
