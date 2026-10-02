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
// Verified byte-exact against all 5 .ani files in xmas.xpk:
//   u32   clipCount
//   per clip:
//     u32   5, char "ANIM\0"      (length-prefixed tag)
//     u32   entryCount, u32 subFormat, u32 reserved
//     ClipInfo record (80 bytes, only when subFormat==2):
//       float m[16]  (D3D row-major 4x4, identity for ClipInfo)
//       float s[3]   (~1,1,1)
//       u32   durationMs
//     then (entryCount-1) bone tracks, each:
//       rest-pose header (84 bytes): float m[16] + float s[3] +
//                                     u32 keyCount + u32 reserved
//       then (keyCount-1) keyframe records (80 bytes each):
//         float m[16] + float s[3] + u32 timeMs (steps of 160)
//     trailing 76-byte footer (matrix+scale, no time field; purpose
//     undecoded) after the last track.
// Clips with subFormat != 2 (seen: 28, 62) have an undecoded layout —
// AniParser::parse skips them via a tag-boundary scan rather than
// guessing, so later clips/files still parse correctly.
//
// GAP: bone tracks carry no name, only positional index — correlating
// AniBoneTrack order to a mesh's actual Frame names is not done yet.
// ============================================================

struct AniKeyframe {
    float time;          // seconds from clip start
    float posX, posY, posZ;
    float rotX, rotY, rotZ, rotW;  // quaternion
    float scaleX, scaleY, scaleZ;
};

struct AniBoneTrack {
    std::string boneName;  // empty — not stored in the file, see GAP above
    std::vector<AniKeyframe> keyframes;
};

struct AniClip {
    std::string name;      // synthetic ("clip_N") — not stored in the file
    float duration;
    std::vector<AniBoneTrack> tracks;
};

class AniParser {
public:
    // Returns empty vector on failure
    static std::vector<AniClip> parse(const uint8_t* data, size_t size);

    // .ani data is stored raw — this is a passthrough, kept for API
    // symmetry with the MSZIP-compressed .x loader.
    static std::vector<uint8_t> decompress(const uint8_t* data, size_t size);
};
