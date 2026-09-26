// Verifies the exact ground-height/footprint algorithm used in
// ios/PhysicsWorld.mm — reimplemented here in plain C++ so it can run
// against the real level data without Xcode. Build:
//   g++ -std=c++17 -Isrc tools/test_physics.cpp src/AssetManager.cpp \
//       src/LevelParser.cpp src/ElementCatalog.cpp -lz -o test_physics
//   ./test_physics assets/xmas.xpk levels\\000.dat
#include "AssetManager.h"
#include "LevelParser.h"
#include "ElementCatalog.h"
#include <cstdio>
#include <cmath>
#include <set>
#include <string>

static float ResolveScale(float s) {
    float scale = (s >= 1.0f) ? (s / 100.0f) : s;
    if (scale <= 0.0f) scale = 0.01f;
    return scale;
}

struct Footprint { float x, y, z, radius; bool isHazard; std::string name; };

static bool g_scaleRadius = true;

int main(int argc, char** argv) {
    if (argc < 3) { printf("usage: %s xmas.xpk levels\\\\000.dat [noscale]\n", argv[0]); return 1; }
    g_scaleRadius = !(argc > 3 && std::string(argv[3]) == "noscale");
    AssetManager am;
    if (!am.loadXPK(argv[1])) { printf("cannot open xpk\n"); return 1; }

    auto elementsRaw = am.getAssetData("data\\elements.txt");
    if (elementsRaw.empty()) { printf("elements.txt missing\n"); return 1; }
    ElementCatalog &catalog = ElementCatalog::shared();
    catalog.parse(std::string((const char*)elementsRaw.data(), elementsRaw.size()));
    printf("catalog: %zu elements\n", catalog.size());

    auto levelRaw = am.getAssetData(argv[2]);
    if (levelRaw.empty()) { printf("level file missing\n"); return 1; }
    LevelData level = LevelParser::parse(levelRaw.data(), levelRaw.size());
    printf("level: %u entities\n", level.count);

    std::set<std::string> walkable = {"PLATTFORM","RECTFORM","EXIT","ELEVATOR","MOVER","JUMPER"};
    std::set<std::string> hazard   = {"ENEMY","ELEVATORENEMY"};
    std::vector<Footprint> footprints;
    int skippedNoDef=0, skippedNoRadius=0, skippedType=0;

    for (auto& e : level.entities) {
        const ElementDef* def = catalog.find(e.name);
        if (!def) { skippedNoDef++; continue; }
        bool isWalkable = walkable.count(def->type) > 0;
        bool isHazard = hazard.count(def->type) > 0;
        if (!isWalkable && !isHazard) { skippedType++; continue; }
        if (def->radius <= 0.0f) { skippedNoRadius++; continue; }
        float scale = g_scaleRadius ? ResolveScale(def->scaling) : 1.0f;
        footprints.push_back({e.x, e.y, e.z, def->radius*scale, isHazard, e.name});
    }
    printf("footprints built: %zu (skipped: noDef=%d noRadius=%d otherType=%d)\n",
           footprints.size(), skippedNoDef, skippedNoRadius, skippedType);

    auto groundHeightAt = [&](float x, float z) -> std::pair<float,bool> {
        float best = 0.0f; bool found = false;
        for (auto& fp : footprints) {
            if (fp.isHazard) continue;
            float dx = x - fp.x, dz = z - fp.z;
            if (dx*dx + dz*dz <= fp.radius*fp.radius) {
                if (!found || fp.y > best) { best = fp.y; found = true; }
            }
        }
        return {best, found};
    };

    // Sanity check: for EVERY entity in the level (not just the spawn), does
    // groundHeightAt(that entity's own x,z) land within a small tolerance of
    // that entity's own y? If radii/positions were wrong this would mismatch
    // constantly; if they're right, walkable objects should mostly find
    // themselves (or an overlapping platform at the same height).
    int checked = 0, matched = 0, mismatched = 0, noPlatform = 0;
    for (auto& e : level.entities) {
        const ElementDef* def = catalog.find(e.name);
        if (!def) continue;
        bool isWalkable = walkable.count(def->type) > 0;
        if (!isWalkable) continue;
        checked++;
        auto [h, found] = groundHeightAt(e.x, e.z);
        if (!found) { noPlatform++; continue; }
        if (std::fabs(h - e.y) < 1.0f) matched++; else mismatched++;
    }
    printf("\nself-consistency check (does each platform find ground near its own height?):\n");
    printf("  checked=%d matched=%d mismatched=%d noPlatformFound=%d\n", checked, matched, mismatched, noPlatform);

    // Spawn point: first entity in the file (matches LevelRenderer.mm's
    // `haveStart` — the first placed object sets _target, Santa's start).
    // Coverage test: platforms sit on a 3.0-unit grid (see LevelRenderer.h).
    // If radius is right, WALKING BETWEEN two adjacent same-height platforms
    // (a point 1.5 units from each, i.e. the shared edge) should still find
    // ground — a real platform's surface has no gap at the seam between
    // two tiles. If radius is too small, that midpoint falls through.
    int seamsChecked = 0, seamsCovered = 0;
    for (size_t i = 0; i < footprints.size(); i++) {
        for (size_t j = i + 1; j < footprints.size(); j++) {
            auto& a = footprints[i]; auto& b = footprints[j];
            if (a.isHazard || b.isHazard) continue;
            float dx = a.x - b.x, dz = a.z - b.z;
            float dist = std::sqrt(dx*dx + dz*dz);
            if (dist < 2.9f || dist > 3.1f) continue;          // only direct grid neighbours
            if (std::fabs(a.y - b.y) > 0.5f) continue;         // only same-height (no stairs/gaps by design)
            float mx = (a.x + b.x) * 0.5f, mz = (a.z + b.z) * 0.5f;
            seamsChecked++;
            auto [h, found] = groundHeightAt(mx, mz);
            if (found && std::fabs(h - a.y) < 1.0f) seamsCovered++;
        }
    }
    printf("\nseam-coverage test (adjacent same-height platforms, gap at the shared edge?):\n");
    printf("  neighbour pairs checked=%d  seam midpoint covered=%d (%.0f%%)\n",
           seamsChecked, seamsCovered, seamsChecked ? 100.0*seamsCovered/seamsChecked : 0.0);

    if (!level.entities.empty()) {
        auto& spawn = level.entities[0];
        auto [h, found] = groundHeightAt(spawn.x, spawn.z);
        printf("\nspawn point: name=\"%s\" pos=(%.2f,%.2f,%.2f)\n", spawn.name.c_str(), spawn.x, spawn.y, spawn.z);
        printf("  groundHeightAt(spawn.x,spawn.z) = %s%.2f  (spawn.y=%.2f, diff=%.2f)\n",
               found ? "" : "[NOTHING FOUND] ", h, spawn.y, h - spawn.y);
    }

    // A handful of other sample points across the level bounds, to eyeball
    // that height values are sane (not wildly negative/huge, not all zero).
    printf("\nsample platform heights (first 10 walkable footprints):\n");
    int shown = 0;
    for (auto& fp : footprints) {
        if (fp.isHazard || shown >= 10) continue;
        printf("  %-24s pos=(%.2f,%.2f,%.2f) radius=%.3f\n", fp.name.c_str(), fp.x, fp.y, fp.z, fp.radius);
        shown++;
    }
    return 0;
}
