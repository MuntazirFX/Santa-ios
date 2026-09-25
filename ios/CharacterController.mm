#import "CharacterController.h"

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
    
    // Ground check (simple — replace with level collision later)
    if (_position.y <= 0) {
        _position.y = 0;
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
}

@end
