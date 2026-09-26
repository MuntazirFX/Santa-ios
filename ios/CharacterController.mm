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
        _radius = 1.0f;
        
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
    
    // Ground check — real level ground when a PhysicsWorld is attached
    // (raycasts against PLATTFORM/RECTFORM objects), flat y=0 otherwise.
    float ground = _physicsWorld ? [_physicsWorld groundHeightAtX:_position.x z:_position.z] : 0.0f;
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

    // Enemy collision (only meaningful once physicsWorld is wired up by
    // the caller with the current level's entities).
    if (_physicsWorld && _state != CharacterStateHurt) {
        if ([_physicsWorld checkCollisionAtPosition:_position radius:_radius]) {
            _state = CharacterStateHurt;
        }
    }
}

@end
