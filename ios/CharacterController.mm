#import "CharacterController.h"
#import "PhysicsWorld.h"

@implementation CharacterController {
    BOOL _inputLeft;
    BOOL _inputRight;
    BOOL _jumpTriggered;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _position = simd_make_float3(0, 0, 0);
        _velocity = simd_make_float3(0, 0, 0);
        _facingDirection = 1.0f;
        _state = CharacterStateIdle;
        _isOnGround = YES;
        
        _walkSpeed = 4.0f;
        _jumpVelocity = 8.0f;
        _gravity = -20.0f;
        
        _inputLeft = NO;
        _inputRight = NO;
        _jumpTriggered = NO;
    }
    return self;
}

- (void)setInputLeft:(BOOL)left {
    _inputLeft = left;
}

- (void)setInputRight:(BOOL)right {
    _inputRight = right;
}

- (void)triggerJump {
    _jumpTriggered = YES;
}

- (void)update:(float)deltaTime {
    // Horizontal movement
    float moveX = 0;
    if (_inputLeft) moveX -= 1.0f;
    if (_inputRight) moveX += 1.0f;
    
    if (moveX != 0) {
        _facingDirection = moveX > 0 ? 1.0f : -1.0f;
        _state = _isOnGround ? CharacterStateWalking : _state;
    } else if (_isOnGround) {
        _state = CharacterStateIdle;
    }
    
    _velocity.x = moveX * _walkSpeed;
    
    // Jump
    if (_jumpTriggered && _isOnGround) {
        _velocity.y = _jumpVelocity;
        _isOnGround = NO;
        _state = CharacterStateJumping;
    }
    _jumpTriggered = NO;
    
    // Gravity
    _velocity.y += _gravity * deltaTime;
    
    // Apply velocity
    _position += _velocity * deltaTime;
    
    // Ground check: real per-footprint height from PhysicsWorld when
    // available (level loaded), otherwise the old flat y=0 behavior.
    float ground = self.physicsWorld ? [self.physicsWorld groundHeightAtX:_position.x z:_position.z] : 0.0f;
    if (_position.y <= ground) {
        _position.y = ground;
        _velocity.y = 0;
        _isOnGround = YES;
        if (_state == CharacterStateJumping || _state == CharacterStateFalling) {
            _state = CharacterStateIdle;
        }
    } else {
        _isOnGround = NO;
        if (_state != CharacterStateJumping) {
            _state = CharacterStateFalling;
        }
    }

    // Hazard collision (enemies): just flags state for now — caller
    // decides what "Hurt" means (lose a life, knockback, etc).
    if (self.physicsWorld && [self.physicsWorld checkCollisionAtPosition:_position radius:0.5f]) {
        _state = CharacterStateHurt;
    }
}

@end
