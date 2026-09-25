#pragma once
#include <cstdint>
#include <string>
#include <vector>

// ============================================================
// .ani File Parser
//
// IMPORTANT: .ani files are RAW little-endian binary — they are NOT
// MSZIP-compressed like the .x files (no "CK" blocks; running them
// through decompressMSZip returns 0 bytes).
//
// What has been verified against all 5 .ani files in xmas.xpk:
//   u32   clipCount           (santa 9, troll 4, snowman 4, raven 1, waypoint 1)
//   u32   5                   (length of the following string)
//   char  "ANIM\0"            (5 bytes: length-prefixed tag)
//   u32 a, u32 b, u32 0       (per-clip header, meaning not decoded yet)
//   then 80-byte key records:
//       float m[16]           (D3D row-major 4x4 matrix: rotation rows,
//                              translation in row 3, w column 0,0,0,1)
//       float s[3]            (~1,1,1)
//       u32   time            (milliseconds, steps of 160)
// Records do not tile the whole file (per-clip headers interleave), so a
// full parser still needs the clip/bone boundaries decoded.
//
// Clips are named animation sequences:
//   - "idle"  (0)
//   - "walk"  (1)
//   - "jump"  (2)
//   - "hurt"  (3)
//   - etc.
// ============================================================

struct AniKeyframe {
    float time;          // seconds from clip start
    float posX, posY, posZ;
    float rotX, rotY, rotZ, rotW;  // quaternion
    float scaleX, scaleY, scaleZ;
};

struct AniBoneTrack {
    std::string boneName;
    std::vector<AniKeyframe> keyframes;
};

struct AniClip {
    std::string name;
    float duration;
    std::vector<AniBoneTrack> tracks;
};

class AniParser {
public:
    // Returns empty vector on failure
    static std::vector<AniClip> parse(const uint8_t* data, size_t size);
    
    // Decompress .ani file (same MSZIP as .x)
    static std::vector<uint8_t> decompress(const uint8_t* data, size_t size);
};
