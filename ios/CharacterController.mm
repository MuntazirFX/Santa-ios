#import "CharacterController.h"
#import "PhysicsWorld.h"

@implementation CharacterController {
    float _moveX, _moveZ;
    BOOL _jumpTriggered;
    float _invulnTimer;   // seconds remaining where hazard hits are ignored
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _position = simd_make_float3(0, 0, 0);
        _velocity = simd_make_float3(0, 0, 0);
        _facingAngle = 0.0f;
        _state = CharacterStateIdle;
        _isOnGround = YES;
        _lives = 3;

        _walkSpeed = 4.0f;
        _jumpVelocity = 8.0f;
        _gravity = -20.0f;
        _radius = 1.0f;

        _moveX = 0.0f;
        _moveZ = 0.0f;
        _jumpTriggered = NO;
        _invulnTimer = 0.0f;
    }
    return self;
}

- (void)setMoveDirectionX:(float)dx z:(float)dz {
    _moveX = dx;
    _moveZ = dz;
}

- (void)triggerJump {
    _jumpTriggered = YES;
}

- (void)update:(float)deltaTime physics:(PhysicsWorld *)physics {
    if (_invulnTimer > 0.0f) _invulnTimer -= deltaTime;

    // Horizontal movement (world X/Z ground plane).
    float moveX = _moveX, moveZ = _moveZ;
    float moveLenSq = moveX*moveX + moveZ*moveZ;
    BOOL moving = moveLenSq > 0.0001f;

    if (moving) {
        _facingAngle = atan2f(moveX, moveZ);   // 0 = +Z, matches LevelModelMatrix's angle convention
        if (_isOnGround && _state != CharacterStateHurt) _state = CharacterStateWalking;
    } else if (_isOnGround && _state != CharacterStateHurt) {
        _state = CharacterStateIdle;
    }

    _velocity.x = moveX * _walkSpeed;
    _velocity.z = moveZ * _walkSpeed;

    // Jump
    if (_jumpTriggered && _isOnGround && _state != CharacterStateHurt) {
        _velocity.y = _jumpVelocity;
        _isOnGround = NO;
        _state = CharacterStateJumping;
    }
    _jumpTriggered = NO;

    // Gravity
    _velocity.y += _gravity * deltaTime;

    // Apply velocity
    _position += _velocity * deltaTime;

    // Ground check against the real level, or a flat plane at physics.groundY
    // (or y=0) if no level/physics world is available yet.
    float ground = physics ? [physics groundHeightAtX:_position.x z:_position.z] : 0.0f;
    if (_position.y <= ground) {
        _position.y = ground;
        _velocity.y = 0;
        _isOnGround = YES;
        if (_state == CharacterStateJumping || _state == CharacterStateFalling) {
            _state = moving ? CharacterStateWalking : CharacterStateIdle;
        }
    } else {
        _isOnGround = NO;
        if (_state != CharacterStateJumping && _state != CharacterStateHurt) {
            _state = CharacterStateFalling;
        }
    }

    // Hazard collision (enemies). A short invulnerability window after a
    // hit stops one touch from draining every life in a single second.
    if (physics && _invulnTimer <= 0.0f) {
        if ([physics checkCollisionAtPosition:_position radius:_radius]) {
            _lives = MAX(0, _lives - 1);
            _state = CharacterStateHurt;
            _invulnTimer = 1.5f;
            // Small knockback so the hit is visible and Santa isn't stuck
            // standing inside the hazard next frame.
            _velocity.x = -moveX * 2.0f;
            _velocity.z = -moveZ * 2.0f;
            _velocity.y = _jumpVelocity * 0.5f;
        }
    }
    if (_state == CharacterStateHurt && _invulnTimer <= 0.0f) {
        _state = _isOnGround ? (moving ? CharacterStateWalking : CharacterStateIdle) : CharacterStateFalling;
    }
}

@end
