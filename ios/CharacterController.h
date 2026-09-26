#import <Foundation/Foundation.h>
#import <simd/simd.h>

// ============================================================
// Character Controller
//
// Manages Santa's movement, input, and animation state on the level's
// X/Z ground plane (levels place platforms across both axes — see
// LevelRenderer.h — so movement isn't left/right-only).
// ============================================================

@class PhysicsWorld;

typedef NS_ENUM(NSInteger, CharacterState) {
    CharacterStateIdle,
    CharacterStateWalking,
    CharacterStateJumping,
    CharacterStateFalling,
    CharacterStateHurt
};

@interface CharacterController : NSObject

// Transform
@property (nonatomic) simd_float3 position;
@property (nonatomic) simd_float3 velocity;
@property (nonatomic) float facingAngle;   // radians about Y, 0 = +Z (matches LevelModelMatrix's angle)

// State
@property (nonatomic) CharacterState state;
@property (nonatomic) BOOL isOnGround;
@property (nonatomic) int lives;           // decremented by touchHazard; not itself game-over logic

// Movement parameters
@property (nonatomic) float walkSpeed;      // default 4.0 (world units/sec, same units as level grid)
@property (nonatomic) float jumpVelocity;   // default 8.0
@property (nonatomic) float gravity;        // default -20.0
@property (nonatomic) float radius;         // collision radius for hazard checks, default 1.0

// Input, set every frame by whatever UI drives movement (joystick, buttons,
// etc.) — X/Z are world-space ground-plane axes, magnitude should be 0..1
// (a diagonal joystick push naturally gives length ~1 already; this does
// not renormalize a shorter push, so partial pushes stay partial-speed).
- (void)setMoveDirectionX:(float)dx z:(float)dz;
- (void)triggerJump;

// Advance the simulation one frame. `physics` supplies real ground height
// and hazard checks from the loaded level; pass nil to fall back to a
// flat plane at physics.groundY (0), e.g. before a level has loaded.
- (void)update:(float)deltaTime physics:(PhysicsWorld *)physics;

@end
