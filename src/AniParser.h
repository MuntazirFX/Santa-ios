#pragma once
#include <cstdint>
#include <string>
#include <vector>

// ============================================================
// .ani File Parser
//
// .ani files are RAW little-endian binary — NOT MSZIP-compressed like the
// .x files (no "CK" blocks; decompress() is a passthrough kept only so
// callers don't need to special-case .ani vs .x loading).
//
// FULL FORMAT (reverse-engineered + byte-exact verified against every clip
// of weihnachtsman_000.ani, rabe_000.ani and winter_troll_000.ani — the
// three .ani files whose clips all use sub-format b==2; see below for the
// two files that contain a different, still-undecoded sub-format):
//
//   u32   clipCount
//   clip[clipCount]:
//     u32   tagLen              (always 5 in every sample seen)
//     char  tag[tagLen]         ("ANIM\0" — a generic block tag, not a name)
//     u32   entryCount          (= boneTrackCount + 1)
//     u32   subFormat           (2 == standard skeletal-track clip, the only
//                                 one decoded below; other values — seen as
//                                 28 and 62 in a couple of one-off clips —
//                                 are a different, still-unknown layout and
//                                 are currently skipped, not parsed)
//     u32   reserved            (0 in every sample seen)
//     ClipInfo record (80 bytes): float m[16] (identity in every sample —
//                                 unused), float scale[3] (unused),
//                                 u32 durationMs
//     if subFormat == 2:
//       boneTrack[entryCount - 1]:
//         track header (84 bytes):
//           float restMatrix[16]  (D3D row-major 4x4: 3x3 rotation in the
//                                  top-left, translation in row 3 — m[12..14]
//                                  — w column (m[3],m[7],m[11],m[15]) is
//                                  always (0,0,0,1))
//           float restScale[3]
//           u32   keyCount         (>= 1; keyCount-1 explicit keyframe
//                                   records follow — the header's own
//                                   restMatrix/restScale doubles as the
//                                   implicit keyframe at t=0)
//           u32   reserved         (0 in every sample seen)
//         keyframe[keyCount - 1]:
//           float matrix[16]      (same row-major layout as restMatrix)
//           float scale[3]
//           u32   timeMs           (steps of 160ms in every sample seen)
//       footer record (76 bytes): float matrix[16], float scale[3] — no
//         trailing field. Present after every subFormat==2 clip's last
//         track. Purpose not decoded (candidates: a duplicate/root-motion
//         transform, or unused padding) — parsed and discarded for now.
//
// Byte-exact verification: parsing entryCount-1 tracks + the 76-byte footer
// lands EXACTLY on the next clip's tag (or EOF) for all 9 santa clips, all
// 4 troll clips, all 1 raven clip, and the first 2 (of 4) snowman clips —
// every clip in the sample set with subFormat==2.
//
// NOT YET DECODED: schneemann_000.ani's last 2 clips and waypoint_000.ani's
// only clip use subFormat 28 / 62 respectively — a different record layout
// (e.g. one track header there reads keyCount==320, far outside the normal
// skeletal range, so it is not simply "more of the same"). These are almost
// certainly non-skeletal special clips (a single marker/prop transform)
// rather than character animation, so they're low priority; parse() detects
// them via subFormat, skips their bytes using the same tag-boundary scan
// used for clip separation (so later clips in the same file still parse
// correctly), and returns them as a clip with duration set but an empty
// track list.
//
// Bone identity: keyframe records carry NO bone name or index — tracks are
// positional (track i is always the i-th bone in the clip, same order every
// clip in a file). AniBoneTrack::boneName is left empty; use trackIndex to
// correlate against the mesh's own bone/Frame order (from XFileParser's
// Frame hierarchy) at the call site — this file has no visibility into that
// mapping. For weihnachtsman_000.ani, 70 tracks vs. the mesh's 72 Frames
// (see XFileParser notes) — the 2 extra Frames are almost certainly the
// scene-root and the mesh-holder frame, which aren't independently animated
// bones, but this hasn't been confirmed against the actual Frame names yet.
//
// Named clips (santa: idle/walk/jump/hurt/... by rough position/duration)
// are NOT verified from the data — the tag is generic "ANIM" for every
// clip, so AniClip::name is just a positional label ("ANIM_0", "ANIM_1",
// ...); do not treat it as a real animation name without further evidence.
// ============================================================

struct AniKeyframe {
    float time;          // seconds from clip start (converted from the file's ms)
    float posX, posY, posZ;
    float rotX, rotY, rotZ, rotW;  // quaternion, derived from the row-major rotation matrix
    float scaleX, scaleY, scaleZ;  // taken directly from the file's explicit scale field
};

struct AniBoneTrack {
    std::string boneName;   // always empty — see "Bone identity" above
    int trackIndex = -1;    // position of this track within its clip (0-based)
    std::vector<AniKeyframe> keyframes;  // includes the implicit t=0 keyframe from the track header
};

struct AniClip {
    std::string name;
    float duration = 0.0f;  // seconds
    int subFormat = 0;      // 2 == standard skeletal clip (tracks populated); anything else == unsupported, tracks empty
    std::vector<AniBoneTrack> tracks;
};

class AniParser {
public:
    // Returns empty vector on failure (buffer too small / no clipCount).
    // Never throws; malformed individual clips are skipped (see header notes).
    static std::vector<AniClip> parse(const uint8_t* data, size_t size);

    // .ani data is stored raw — this is a passthrough, kept for API symmetry
    // with XFileParser::decompressMSZip so callers can treat .ani/.x loading
    // uniformly.
    static std::vector<uint8_t> decompress(const uint8_t* data, size_t size);
};
