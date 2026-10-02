#import "PhysicsWorld.h"
#include "../src/AssetManager.h"
#include "../src/LevelParser.h"
#include "../src/ElementCatalog.h"
#include <vector>
#include <string>
#include <set>
#include <cmath>
#include <algorithm>

struct PWFootprint {
    float x, y, z, radius;
    bool isHazard;
};

@implementation PhysicsWorld {
    std::vector<PWFootprint> _footprints;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _groundY = 0.0f;
    }
    return self;
}

static float PWResolveScale(float s) {
    // elements.txt SCALING values are mixed: some already fractions (0.014),
    // some percent-like (>=1). Same normalization verified in test_physics.cpp.
    float scale = (s >= 1.0f) ? (s / 100.0f) : s;
    if (scale <= 0.0f) scale = 0.01f;
    return scale;
}

- (BOOL)loadLevelFootprints:(NSString *)levelPath fromXPK:(NSString *)xpkPath {
    _footprints.clear();

    AssetManager am;
    if (!am.loadXPK(std::string([xpkPath UTF8String]))) return NO;

    auto elementsRaw = am.getAssetData("data\\elements.txt");
    if (elementsRaw.empty()) return NO;
    ElementCatalog &catalog = ElementCatalog::shared();
    catalog.parse(std::string((const char *)elementsRaw.data(), elementsRaw.size()));

    auto levelRaw = am.getAssetData(std::string([levelPath UTF8String]));
    if (levelRaw.empty()) return NO;
    LevelData level = LevelParser::parse(levelRaw.data(), levelRaw.size());

    static const std::set<std::string> kWalkable = {"PLATTFORM", "RECTFORM", "EXIT", "ELEVATOR", "MOVER", "JUMPER"};
    static const std::set<std::string> kHazard = {"ENEMY", "ELEVATORENEMY"};

    // Platforms in this data sit on a 3.0-unit grid (see LevelRenderer.h);
    // the catalog's own RADIUS/SCALING values are far too small to cover a
    // tile edge-to-edge (verified: 0% seam coverage with the raw radius in
    // tools/test_physics.cpp). Until the real per-tile footprint size is
    // reverse-engineered from data, we floor the walkable radius at 1.6
    // (half the 3.0 grid spacing + a small margin) so adjacent same-height
    // platforms don't have a gap at their shared edge. Hazards keep their
    // real catalog radius since seam coverage doesn't apply to them.
    const float kMinWalkableRadius = 1.6f;

    for (auto &e : level.entities) {
        const ElementDef *def = catalog.find(e.name);
        if (!def) continue;
        bool isWalkable = kWalkable.count(def->type) > 0;
        bool isHazard = kHazard.count(def->type) > 0;
        if (!isWalkable && !isHazard) continue;
        if (def->radius <= 0.0f) continue;

        float radius = def->radius * PWResolveScale(def->scaling);
        if (isWalkable) radius = std::max(radius, kMinWalkableRadius);

        PWFootprint fp;
        fp.x = e.x; fp.y = e.y; fp.z = e.z;
        fp.radius = radius;
        fp.isHazard = isHazard;
        _footprints.push_back(fp);
    }

    return !_footprints.empty();
}

- (float)groundHeightAtX:(float)x z:(float)z {
    float best = _groundY;
    bool found = false;
    for (auto &fp : _footprints) {
        if (fp.isHazard) continue;
        float dx = x - fp.x, dz = z - fp.z;
        if (dx * dx + dz * dz <= fp.radius * fp.radius) {
            if (!found || fp.y > best) { best = fp.y; found = true; }
        }
    }
    return best;
}

- (BOOL)checkCollisionAtPosition:(simd_float3)position radius:(float)radius {
    for (auto &fp : _footprints) {
        if (!fp.isHazard) continue;
        float dx = position.x - fp.x, dz = position.z - fp.z;
        float rr = fp.radius + radius;
        if (dx * dx + dz * dz <= rr * rr) {
            // Only count it if the character is roughly at the hazard's
            // height (within one step), not anywhere above/below it.
            if (std::fabs(position.y - fp.y) < 2.0f) return YES;
        }
    }
    return NO;
}

@end
