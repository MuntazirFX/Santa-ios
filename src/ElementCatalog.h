#pragma once
#include <string>
#include <unordered_map>
#include <vector>

// ============================================================
// data/elements.txt catalog  (101 ELEMENT blocks, verified)
//
//   ELEMENT   "TROLL"
//   FILE      "gfx\winter_troll_000.ani"
//   RADIUS    1.6
//   SCALING   0.014
//   SPEED     1.9          (optional)
//   WALKANIM  0            (optional)
//   JUMPHEIGHT / VERTICALOFFSET / FRICTION / ROTATION / EFFECT (optional)
//   TYPE      ENEMY
//
// TYPE values present: ENEMY, ELEVATORENEMY, RECTFORM, PLATTFORM, EXIT,
// ELEVATOR, MOVER, JUMPER, DECO, BONUS, EXTRALIFE, SAVEPOINT.
//
// Every object name used by the 13 level files (6313 objects) exists in
// this catalog, so the catalog is the authoritative source for an
// object's model + behaviour category.
// ============================================================
struct ElementDef {
    std::string name;
    std::string file;        // as written, e.g. "gfx\Snow_Corner.X" or "gfx\rabe_000.ani"
    std::string meshFile;    // file with ".ani" turned into ".x" (skinned models: mesh in .x, motion in .ani)
    std::string aniFile;     // non-empty only when FILE pointed at an .ani
    std::string type;
    std::string effect;      // e.g. "effects\fire.txt"
    float radius = 0.0f;
    float scaling = 1.0f;
    float speed = 0.0f;
    float jumpHeight = 0.0f;
    float verticalOffset = 0.0f;
    float friction = 0.0f;
    float rotation = 0.0f;
    int   walkAnim = -1;
};

class ElementCatalog {
public:
    // Parse the raw text of elements.txt (CRLF or LF). Returns number of elements.
    size_t parse(const std::string& text);
    // Exact name first, then trimmed / case-insensitive fallback. nullptr if unknown.
    const ElementDef* find(const std::string& name) const;
    size_t size() const { return defs_.size(); }
    const std::vector<ElementDef>& all() const { return defs_; }

    // Process-wide instance used by LevelParser::getEntityType().
    static ElementCatalog& shared();

private:
    std::vector<ElementDef> defs_;
    std::unordered_map<std::string, size_t> byName_;   // exact
    std::unordered_map<std::string, size_t> byLower_;  // trimmed + lowercased
};
