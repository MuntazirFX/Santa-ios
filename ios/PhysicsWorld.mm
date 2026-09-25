#import "PhysicsWorld.h"

@implementation PhysicsWorld

- (instancetype)init {
    self = [super init];
    if (self) {
        _groundY = 0.0f;
    }
    return self;
}

- (BOOL)checkCollisionAtPosition:(simd_float3)position radius:(float)radius {
    // TODO: Check against level entities (loaded from .dat)
    return NO;
}

- (float)groundHeightAtX:(float)x z:(float)z {
    // TODO: Raycast against level geometry
    return _groundY;
}

@end
