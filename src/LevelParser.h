#pragma once
#include <cstdint>
#include <string>
#include <vector>

// ============================================================
// Level .dat File Parser (C++ side)
//
// File structure:
//   DWORD count
//   Record[count] = 60 bytes each:
//     char  name[32]     — NUL-terminated entity name
//     float x, y, z      — world position
//     float rx, ry, rz   — rotation or secondary position
//     int32 variant      — variant/type code
// ============================================================

// ✅ RENAMED to avoid conflict with ObjC LevelEntity class in LevelLoader.h
struct RawLevelEntity {
    std::string name;        // e.g. "TREE A"
    float x, y, z;            // world position
    float rotX, rotY, rotZ;   // rotation or linked position
    int32_t variant;          // type variant
};

struct LevelData {
    uint32_t count;
    std::vector<RawLevelEntity> entities;
};

class LevelParser {
public:
    static LevelData parse(const uint8_t* data, size_t size);
    static std::string getEntityType(const std::string& name);
};
