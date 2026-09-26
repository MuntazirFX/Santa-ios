#import "PhysicsWorld.h"
#import "GameEngine.h"
#include "ElementCatalog.h"
#include <string>
#include <vector>

// Note: elements.txt's RADIUS is already expressed in final world units.
// A seam-coverage test against the real level 000 data confirmed this —
// multiplying RADIUS by the mesh's visual SCALING factor (LevelRenderer.mm's
// percent-vs-direct rule) left 0% of the seams between adjacent same-height
// platforms covered (Santa would fall through every gap between tiles);
// using RADIUS as-is covered 95% of them, matching the visual (platforms
// tile edge-to-edge on the level's 3.0-unit grid). So collision uses
// def->radius directly and never touches def->scaling.

@implementation PhysicsWorld {
    std::vector<PhysicsFootprint> _footprints;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _groundY = 0.0f;
    }
    return self;
}

- (void)buildFromLevelObjects:(NSArray<LevelObject *> *)objects {
    _footprints.clear();
    ElementCatalog &catalog = ElementCatalog::shared();

    static NSSet<NSString *> *walkable = [NSSet setWithArray:@[
        @"PLATTFORM", @"RECTFORM", @"EXIT", @"ELEVATOR", @"MOVER", @"JUMPER"
    ]];
    static NSSet<NSString *> *hazard = [NSSet setWithArray:@[
        @"ENEMY", @"ELEVATORENEMY"
    ]];

    for (LevelObject *o in objects) {
        const ElementDef *def = catalog.find(std::string([o.objectName UTF8String]));
        if (!def) continue;

        // Walkable surfaces: everything you can stand on. EXIT/ELEVATOR
        // platforms have a surface too, so Santa can stand on them while
        // they (later) get animated; MOVER/JUMPER are also platform-like.
        // DECO/BONUS/EXTRALIFE/SAVEPOINT have no meaningful "top surface"
        // for standing (trees, presents, pickups) so they're excluded —
        // including them would let Santa float on top of a present.
        NSString *type = [NSString stringWithUTF8String:def->type.c_str()];
        bool isWalkable = [walkable containsObject:type];
        bool isHazard = [hazard containsObject:type];
        if (!isWalkable && !isHazard) continue;
        if (def->radius <= 0.0f) continue;

        PhysicsFootprint fp;
        fp.x = o.x; fp.y = o.y; fp.z = o.z;
        fp.radius = def->radius;   // world units already — do not scale, see ResolveScale comment
        fp.isHazard = isHazard ? YES : NO;
        _footprints.push_back(fp);
    }
}

- (float)groundHeightAtX:(float)x z:(float)z {
    float best = _groundY;
    bool found = false;
    for (const auto &fp : _footprints) {
        if (fp.isHazard) continue;
        float dx = x - fp.x, dz = z - fp.z;
        float r = fp.radius;
        if (dx*dx + dz*dz <= r*r) {
            if (!found || fp.y > best) { best = fp.y; found = true; }
        }
    }
    return best;
}

- (BOOL)checkCollisionAtPosition:(simd_float3)position radius:(float)radius {
    for (const auto &fp : _footprints) {
        if (!fp.isHazard) continue;
        float dx = position.x - fp.x, dz = position.z - fp.z;
        float dy = position.y - fp.y;
        float r = fp.radius + radius;
        // Hazards are checked in 3D (not just footprint) since Santa can
        // walk under/over a ground-level enemy without touching it.
        if (dx*dx + dz*dz <= r*r && dy*dy <= (r*r)) return YES;
    }
    return NO;
}

@end
