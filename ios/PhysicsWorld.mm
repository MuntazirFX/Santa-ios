#import "PhysicsWorld.h"
#import "LevelLoader.h"
#import "GameEngine.h"
#import <vector>

static const float kDefaultFootprintRadius = 1.5f; // half a 3.0-unit grid cell, used when RADIUS is missing

// Internal, type-agnostic copy of just what collision needs, so both
// LevelEntity (LevelLoader.h) and LevelObject (GameEngine.h) can feed the
// same solid/actor lists without duplicating the footprint logic per type.
struct PWObj {
    simd_float3 position;
    float radius;
    BOOL isSolid; // PLATTFORM / RECTFORM
    BOOL isActor; // ENEMY / ELEVATORENEMY
};

@implementation PhysicsWorld {
    std::vector<PWObj> _solids;
    std::vector<PWObj> _actors;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _groundY = 0.0f;
        _platformThickness = 1.0f;
    }
    return self;
}

- (void)rebuildFromCount:(NSUInteger)count
                     name:(NSString *(^)(NSUInteger))typeAt
                 position:(simd_float3(^)(NSUInteger))posAt
                   radius:(float(^)(NSUInteger))radAt {
    _solids.clear();
    _actors.clear();
    for (NSUInteger i = 0; i < count; i++) {
        NSString *type = typeAt(i);
        BOOL isSolid = [type isEqualToString:@"PLATTFORM"] || [type isEqualToString:@"RECTFORM"];
        BOOL isActor = [type isEqualToString:@"ENEMY"] || [type isEqualToString:@"ELEVATORENEMY"];
        if (!isSolid && !isActor) continue;
        PWObj o;
        o.position = posAt(i);
        o.radius = radAt(i);
        o.isSolid = isSolid;
        o.isActor = isActor;
        (isSolid ? _solids : _actors).push_back(o);
    }
}

- (void)setEntities:(NSArray<LevelEntity *> *)entities {
    NSArray *arr = entities ?: @[];
    [self rebuildFromCount:arr.count
                       name:^NSString *(NSUInteger i) { return ((LevelEntity *)arr[i]).type; }
                   position:^simd_float3(NSUInteger i) { return ((LevelEntity *)arr[i]).position; }
                     radius:^float(NSUInteger i) { return ((LevelEntity *)arr[i]).radius; }];
}

- (void)setEntitiesFromLevelObjects:(NSArray<LevelObject *> *)objects {
    NSArray *arr = objects ?: @[];
    [self rebuildFromCount:arr.count
                       name:^NSString *(NSUInteger i) { return ((LevelObject *)arr[i]).elementType; }
                   position:^simd_float3(NSUInteger i) {
                       LevelObject *o = arr[i];
                       return simd_make_float3(o.x, o.y, o.z);
                   }
                     radius:^float(NSUInteger i) { return ((LevelObject *)arr[i]).radius; }];
}

static float footprintRadius(const PWObj &o) {
    return o.radius > 0.0f ? o.radius : kDefaultFootprintRadius;
}

- (float)groundHeightAtX:(float)x z:(float)z {
    float best = _groundY;
    BOOL found = NO;
    for (const PWObj &o : _solids) {
        float r = footprintRadius(o);
        float dx = x - o.position.x;
        float dz = z - o.position.z;
        if (dx * dx + dz * dz > r * r) continue;
        // The object's authored Y is its platform's top surface (matches
        // how levels\NNN.dat / elements.txt SCALING are documented in
        // README.md: platform tops land on the object's own Y).
        float top = o.position.y;
        if (!found || top > best) { best = top; found = YES; }
    }
    return best;
}

- (LevelEntity *)collidingEntityAtPosition:(simd_float3)position radius:(float)radius {
    // Kept for API compatibility with the LevelEntity-based path; when the
    // level was fed via setEntitiesFromLevelObjects: this always returns nil
    // (no LevelEntity to hand back) — use checkCollisionAtPosition: instead.
    return nil;
}

- (BOOL)checkCollisionAtPosition:(simd_float3)position radius:(float)radius {
    for (const PWObj &o : _actors) {
        float dx = position.x - o.position.x;
        float dz = position.z - o.position.z;
        float dy = position.y - o.position.y;
        if (fabsf(dy) > 3.0f) continue; // different platform / floor — not a real overlap
        float rSum = radius + footprintRadius(o);
        if (dx * dx + dz * dz <= rSum * rSum) return YES;
    }
    return NO;
}

@end
