#include "AniParser.h"
#include <cstring>
#include <cstdio>
#include <cmath>

namespace {

// Reads a little-endian float/u32 at a byte offset. No bounds checking here
// on purpose — every call site checks the range it's about to read first,
// so a single set of checks covers a whole record instead of one per field.
inline float readF32(const uint8_t* d, size_t off) {
    float v;
    memcpy(&v, d + off, sizeof(float));
    return v;
}
inline uint32_t readU32(const uint8_t* d, size_t off) {
    uint32_t v;
    memcpy(&v, d + off, sizeof(uint32_t));
    return v;
}

// D3D row-major 4x4 -> quaternion. Scale is stored separately in the file
// (see AniParser.h), so the 3x3 block here is assumed already unscaled.
void matrixToQuaternion(const float m[16], float& x, float& y, float& z, float& w) {
    // Row-major: m[row*4 + col]. 3x3 rotation is rows 0-2, cols 0-2.
    float m00 = m[0],  m01 = m[1],  m02 = m[2];
    float m10 = m[4],  m11 = m[5],  m12 = m[6];
    float m20 = m[8],  m21 = m[9],  m22 = m[10];

    float trace = m00 + m11 + m22;
    if (trace > 0.0f) {
        float s = std::sqrt(trace + 1.0f) * 2.0f; // s = 4*w
        w = 0.25f * s;
        x = (m21 - m12) / s;
        y = (m02 - m20) / s;
        z = (m10 - m01) / s;
    } else if (m00 > m11 && m00 > m22) {
        float s = std::sqrt(1.0f + m00 - m11 - m22) * 2.0f; // s = 4*x
        w = (m21 - m12) / s;
        x = 0.25f * s;
        y = (m01 + m10) / s;
        z = (m02 + m20) / s;
    } else if (m11 > m22) {
        float s = std::sqrt(1.0f + m11 - m00 - m22) * 2.0f; // s = 4*y
        w = (m02 - m20) / s;
        x = (m01 + m10) / s;
        y = 0.25f * s;
        z = (m12 + m21) / s;
    } else {
        float s = std::sqrt(1.0f + m22 - m00 - m11) * 2.0f; // s = 4*z
        w = (m10 - m01) / s;
        x = (m02 + m20) / s;
        y = (m12 + m21) / s;
        z = 0.25f * s;
    }
}

AniKeyframe recordToKeyframe(const float m[16], const float scale[3], float timeSeconds) {
    AniKeyframe kf;
    kf.time = timeSeconds;
    kf.posX = m[12];
    kf.posY = m[13];
    kf.posZ = m[14];
    matrixToQuaternion(m, kf.rotX, kf.rotY, kf.rotZ, kf.rotW);
    kf.scaleX = scale[0];
    kf.scaleY = scale[1];
    kf.scaleZ = scale[2];
    return kf;
}

// Finds every clip boundary (byte offset of the u32 tagLen field that starts
// each clip) by scanning for the fixed 9-byte pattern "\x05\x00\x00\x00ANIM\x00".
// This is the ground truth used to bound each clip — verified far more
// reliable than trusting accumulated per-track sizes to land exactly right,
// since a single misread field would otherwise desync every clip after it.
std::vector<size_t> findClipBoundaries(const uint8_t* data, size_t size) {
    static const uint8_t pattern[9] = {0x05, 0x00, 0x00, 0x00, 'A', 'N', 'I', 'M', 0x00};
    std::vector<size_t> boundaries;
    if (size < 9) return boundaries;
    for (size_t i = 0; i + 9 <= size; i++) {
        if (memcmp(data + i, pattern, 9) == 0) {
            boundaries.push_back(i);
        }
    }
    return boundaries;
}

} // namespace

std::vector<uint8_t> AniParser::decompress(const uint8_t* data, size_t size) {
    return std::vector<uint8_t>(data, data + size);
}

std::vector<AniClip> AniParser::parse(const uint8_t* data, size_t size) {
    std::vector<AniClip> clips;
    if (size < 4) return clips;

    uint32_t clipCount = readU32(data, 0);
    if (clipCount == 0 || clipCount > 1000) {
        printf("[AniParser] implausible clipCount %u, aborting\n", clipCount);
        return clips;
    }

    std::vector<size_t> boundaries = findClipBoundaries(data, size);
    if (boundaries.size() != clipCount) {
        printf("[AniParser] clipCount=%u but found %zu clip tags — parsing what was found\n",
               clipCount, boundaries.size());
    }
    if (boundaries.empty()) return clips;

    for (size_t ci = 0; ci < boundaries.size(); ci++) {
        size_t clipStart = boundaries[ci];
        size_t clipEnd = (ci + 1 < boundaries.size()) ? boundaries[ci + 1] : size;

        size_t off = clipStart;
        if (off + 4 > size) break;
        uint32_t tagLen = readU32(data, off); off += 4;
        if (off + tagLen + 12 + 80 > size) {
            printf("[AniParser] clip %zu header runs past end of buffer, skipping\n", ci);
            continue;
        }
        off += tagLen; // skip the tag bytes themselves ("ANIM\0")

        uint32_t entryCount = readU32(data, off);      off += 4;
        uint32_t subFormat  = readU32(data, off);      off += 4;
        /* reserved */                                  off += 4;

        // ClipInfo record (80 bytes): identity matrix + scale (unused) + duration
        uint32_t durationMs = readU32(data, off + 76);
        off += 80;

        AniClip clip;
        clip.name = "ANIM_" + std::to_string(ci);
        clip.duration = durationMs / 1000.0f;
        clip.subFormat = (int)subFormat;

        if (subFormat != 2) {
            // Not the standard skeletal-track layout (see AniParser.h) — skip
            // this clip's body without trying to interpret it, but still land
            // cleanly on the next clip boundary so the rest of the file parses.
            printf("[AniParser] clip %zu ('%s') has unsupported subFormat=%u, skipping its tracks\n",
                   ci, clip.name.c_str(), subFormat);
            clips.push_back(clip);
            continue;
        }

        if (entryCount == 0) {
            printf("[AniParser] clip %zu has entryCount=0, skipping\n", ci);
            clips.push_back(clip);
            continue;
        }
        uint32_t trackCount = entryCount - 1;

        bool ok = true;
        for (uint32_t ti = 0; ti < trackCount; ti++) {
            if (off + 84 > clipEnd) {
                printf("[AniParser] clip %zu track %u header runs past clip boundary, truncating clip\n",
                       ci, ti);
                ok = false;
                break;
            }
            float restMatrix[16];
            for (int i = 0; i < 16; i++) restMatrix[i] = readF32(data, off + i * 4);
            float restScale[3] = { readF32(data, off + 64), readF32(data, off + 68), readF32(data, off + 72) };
            uint32_t keyCount = readU32(data, off + 76);
            // off+80: reserved (always 0 in every sample seen) — not used
            off += 84;

            if (keyCount == 0 || keyCount > 100000) {
                printf("[AniParser] clip %zu track %u implausible keyCount=%u, truncating clip\n",
                       ci, ti, keyCount);
                ok = false;
                break;
            }
            uint32_t explicitKeys = keyCount - 1;
            if (off + (size_t)explicitKeys * 80 > clipEnd) {
                printf("[AniParser] clip %zu track %u keyframes run past clip boundary, truncating clip\n",
                       ci, ti);
                ok = false;
                break;
            }

            AniBoneTrack track;
            track.trackIndex = (int)ti;
            track.keyframes.reserve(keyCount);
            // Implicit keyframe at t=0 from the track header itself.
            track.keyframes.push_back(recordToKeyframe(restMatrix, restScale, 0.0f));

            for (uint32_t ki = 0; ki < explicitKeys; ki++) {
                float m[16];
                for (int i = 0; i < 16; i++) m[i] = readF32(data, off + i * 4);
                float s[3] = { readF32(data, off + 64), readF32(data, off + 68), readF32(data, off + 72) };
                uint32_t timeMs = readU32(data, off + 76);
                off += 80;
                track.keyframes.push_back(recordToKeyframe(m, s, timeMs / 1000.0f));
            }

            clip.tracks.push_back(std::move(track));
        }

        if (ok) {
            // 76-byte footer after the last track (matrix + scale, no time field).
            // Purpose not decoded — consumed and discarded, see AniParser.h.
            if (off + 76 <= clipEnd) {
                off += 76;
            }
            if (off != clipEnd) {
                printf("[AniParser] clip %zu ('%s') ended %zd bytes off from the next clip boundary "
                       "(parsed %d tracks) — data after the mismatch may be misaligned\n",
                       ci, clip.name.c_str(), (long)(off - clipEnd), (int)clip.tracks.size());
            }
        }

        clips.push_back(std::move(clip));
    }

    printf("[AniParser] parsed %zu clip(s)\n", clips.size());
    return clips;
}
