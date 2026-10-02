#include "AniParser.h"
#include "XFileParser.h"
#include <cstring>
#include <cstdio>
#include <cmath>

std::vector<uint8_t> AniParser::decompress(const uint8_t* data, size_t size) {
    // .ani data is stored raw (see AniParser.h) — nothing to decompress.
    return std::vector<uint8_t>(data, data + size);
}

namespace {

// Row-major D3D-style 4x4 (rows are basis vectors; translation in row 3:
// m[12],m[13],m[14]) -> quaternion (x,y,z,w) + translation, matching the
// convention already verified for Santa's bind pose (bone0 translation
// 63.07 in y == the known-correct rest pose).
static void matrixToQuatTranslation(const float m[16], float& qx, float& qy, float& qz, float& qw,
                                     float& tx, float& ty, float& tz) {
    tx = m[12]; ty = m[13]; tz = m[14];

    // Upper-left 3x3, read as rows (m[0..2], m[4..6], m[8..10]).
    float m00 = m[0], m01 = m[1], m02 = m[2];
    float m10 = m[4], m11 = m[5], m12_ = m[6];
    float m20 = m[8], m21 = m[9], m22 = m[10];

    float trace = m00 + m11 + m22;
    if (trace > 0.0f) {
        float s = std::sqrt(trace + 1.0f) * 2.0f;
        qw = 0.25f * s;
        qx = (m21 - m12_) / s;
        qy = (m02 - m20) / s;
        qz = (m10 - m01) / s;
    } else if (m00 > m11 && m00 > m22) {
        float s = std::sqrt(1.0f + m00 - m11 - m22) * 2.0f;
        qw = (m21 - m12_) / s;
        qx = 0.25f * s;
        qy = (m01 + m10) / s;
        qz = (m02 + m20) / s;
    } else if (m11 > m22) {
        float s = std::sqrt(1.0f + m11 - m00 - m22) * 2.0f;
        qw = (m02 - m20) / s;
        qx = (m01 + m10) / s;
        qy = 0.25f * s;
        qz = (m12_ + m21) / s;
    } else {
        float s = std::sqrt(1.0f + m22 - m00 - m11) * 2.0f;
        qw = (m10 - m01) / s;
        qx = (m02 + m20) / s;
        qy = (m12_ + m21) / s;
        qz = 0.25f * s;
    }
}

// Reads a length-prefixed tag: u32 strlen, then strlen bytes.
static bool readTag(const uint8_t* data, size_t size, size_t& off, std::string& outTag) {
    if (off + 4 > size) return false;
    uint32_t strlen_;
    memcpy(&strlen_, data + off, 4);
    off += 4;
    if (off + strlen_ > size) return false;
    outTag.assign((const char*)data + off, strlen_);
    off += strlen_;
    return true;
}

// Scans forward for the next clip tag (u32 5 + "ANIM\0") so an
// undecoded subFormat (e.g. 28, 62 — seen in schneemann/waypoint) can be
// skipped without desyncing the rest of the file.
static bool scanForNextClipTag(const uint8_t* data, size_t size, size_t from, size_t& found) {
    static const uint8_t pattern[9] = {5,0,0,0,'A','N','I','M',0};
    if (from + 9 > size) return false;
    for (size_t i = from; i + 9 <= size; i++) {
        if (memcmp(data + i, pattern, 9) == 0) {
            found = i;
            return true;
        }
    }
    return false;
}

} // namespace

std::vector<AniClip> AniParser::parse(const uint8_t* data, size_t size) {
    std::vector<AniClip> clips;
    if (size < 4) return clips;

    uint32_t clipCount;
    memcpy(&clipCount, data, 4);
    size_t off = 4;

    for (uint32_t c = 0; c < clipCount && off < size; c++) {
        size_t clipStart = off;
        std::string tag;
        if (!readTag(data, size, off, tag)) break;

        if (off + 12 > size) break;
        uint32_t entryCount, subFormat, reserved;
        memcpy(&entryCount, data + off, 4); off += 4;
        memcpy(&subFormat, data + off, 4); off += 4;
        memcpy(&reserved, data + off, 4); off += 4;
        (void)reserved;

        if (subFormat != 2) {
            // Undecoded clip layout — skip to the next clip's tag rather
            // than guess, so later clips/files still parse correctly.
            size_t next;
            if (scanForNextClipTag(data, size, off, next)) {
                off = next;
                continue; // don't emit a clip for this one; try again next loop iter without incrementing c logically wrong -> fallthrough below
            } else {
                break; // no more clips found, stop cleanly
            }
        }

        // ClipInfo record (80 bytes): same layout as a keyframe record
        // (matrix16f + scale3f + u32), where the trailing u32 is the
        // clip's total duration in milliseconds.
        if (off + 80 > size) break;
        uint32_t durationMs;
        memcpy(&durationMs, data + off + 76, 4);
        off += 80;

        AniClip clip;
        clip.name = "clip_" + std::to_string(c); // no names stored in the file; index-based
        clip.duration = durationMs / 1000.0f;

        uint32_t numTracks = (entryCount > 0) ? entryCount - 1 : 0;
        bool ok = true;
        for (uint32_t t = 0; t < numTracks; t++) {
            // Rest-pose header (84 bytes): matrix16f + scale3f + keyCount u32 + reserved u32
            if (off + 84 > size) { ok = false; break; }
            float restMat[16];
            memcpy(restMat, data + off, 64);
            float restScale[3];
            memcpy(restScale, data + off + 64, 12);
            uint32_t keyCount, trackReserved;
            memcpy(&keyCount, data + off + 76, 4);
            memcpy(&trackReserved, data + off + 80, 4);
            (void)trackReserved;
            off += 84;

            AniBoneTrack track;
            track.boneName = ""; // not stored in file; caller must correlate by track index (see AniParser.h gap note)

            // Rest pose is keyframe 0 at t=0.
            AniKeyframe restKey;
            restKey.time = 0.0f;
            matrixToQuatTranslation(restMat, restKey.rotX, restKey.rotY, restKey.rotZ, restKey.rotW,
                                     restKey.posX, restKey.posY, restKey.posZ);
            restKey.scaleX = restScale[0]; restKey.scaleY = restScale[1]; restKey.scaleZ = restScale[2];
            track.keyframes.push_back(restKey);

            uint32_t numExtraKeys = (keyCount > 0) ? keyCount - 1 : 0;
            for (uint32_t k = 0; k < numExtraKeys; k++) {
                if (off + 80 > size) { ok = false; break; }
                float mat[16];
                memcpy(mat, data + off, 64);
                float scl[3];
                memcpy(scl, data + off + 64, 12);
                uint32_t timeMs;
                memcpy(&timeMs, data + off + 76, 4);
                off += 80;

                AniKeyframe kf;
                kf.time = timeMs / 1000.0f;
                matrixToQuatTranslation(mat, kf.rotX, kf.rotY, kf.rotZ, kf.rotW, kf.posX, kf.posY, kf.posZ);
                kf.scaleX = scl[0]; kf.scaleY = scl[1]; kf.scaleZ = scl[2];
                track.keyframes.push_back(kf);
            }
            if (!ok) break;
            clip.tracks.push_back(track);
        }
        if (!ok) break;

        // Trailing 76-byte footer after the last track (purpose undecoded —
        // same matrix+scale shape as a keyframe but with no time field).
        if (off + 76 > size) break;
        off += 76;

        clips.push_back(clip);
        (void)clipStart;
    }

    printf("[AniParser] parsed %zu/%u clips (%zu bytes)\n", clips.size(), clipCount, size);
    return clips;
}
