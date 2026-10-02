#import <Foundation/Foundation.h>
#import <simd/simd.h>

@class PhysicsWorld;

// ============================================================
// Character Controller
//
// Manages Santa's movement, input, and animation state.
//
// Current status: SKELETON
// - Position, velocity, ground state
// - Input flags (left, right, jump)
// - Update loop calls physics + animation
// ============================================================

typedef NS_ENUM(NSInteger, CharacterState) {
    CharacterStateIdle,
    CharacterStateWalking,
    CharacterStateJumping,
    CharacterStateFalling,
    CharacterStateHurt
};

@interface CharacterController : NSObject

// Set once after loading a level (AppDelegate/MetalView owns the
// PhysicsWorld instance). If nil, falls back to a flat ground at y=0,
// same as before.
@property (nonatomic, weak) PhysicsWorld *physicsWorld;

// Transform
@property (nonatomic) simd_float3 position;
@property (nonatomic) simd_float3 velocity;
@property (nonatomic) float facingDirection;  // -1 = left, +1 = right

// State
@property (nonatomic) CharacterState state;
@property (nonatomic) BOOL isOnGround;

// Movement parameters
@property (nonatomic) float walkSpeed;      // default 4.0
@property (nonatomic) float jumpVelocity;   // default 8.0
@property (nonatomic) float gravity;        // default -20.0

// Input (set by UI, applied in update)
- (void)setInputLeft:(BOOL)left;
- (void)setInputRight:(BOOL)right;
- (void)triggerJump;

// Update (called every frame)
- (void)update:(float)deltaTime;

@end
