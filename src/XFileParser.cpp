#include "XFileParser.h"
#include <cstring>
#include <cstdio>
#include <sstream>
#include <zlib.h>

std::string& xpkDebugLog() {
    static std::string log;
    return log;
}

static uint32_t readU32(const uint8_t* data, size_t offset) {
    return data[offset] | (data[offset+1] << 8) | (data[offset+2] << 16) | (data[offset+3] << 24);
}

static uint16_t readU16(const uint8_t* data, size_t offset) {
    return data[offset] | (data[offset+1] << 8);
}

// ============================================================
// MSZIP decompression, verified against the real xmas.xpk data.
//
// Each block:
//   - is signalled by a "CK" (0x43 0x4B) marker
//   - raw deflate data (no zlib/gzip wrapper) starts at ckPos+2
//   - decompresses to at most 32768 bytes (the standard MSZIP
//     window size; the final block may be shorter)
//   - EVERY block after the first needs the *previous* block's
//     32768 decompressed bytes set as a preset dictionary
//     (inflateSetDictionary) before calling inflate(), because
//     MSZIP allows LZ77 back-references into the prior block's
//     window. Without this, block 2 onward fails immediately
//     with Z_DATA_ERROR — which is exactly the bug that was
//     silently truncating every asset to its first ~32KB block.
//
// Verified end-to-end on gfx\weihnachtsman_000.x: 6/6 blocks
// decode cleanly and the last block's consumed bytes land
// exactly on the end of the asset's data.
// ============================================================
std::vector<uint8_t> XFileParser::decompressMSZip(const uint8_t* data, size_t size) {
    xpkDebugLog().clear();
    std::vector<uint8_t> output;
    if (size < 4) return output;

    char buf[512];
    size_t offset = 0;
    int blockNum = 0;
    std::vector<uint8_t> dict; // previous block's decompressed output, used as the next block's preset dictionary

    while (offset + 4 <= size && blockNum < 5000) {
        // Find the next "CK" block marker.
        size_t p = offset;
        bool found = false;
        while (p + 1 < size) {
            if (data[p] == 0x43 && data[p + 1] == 0x4B) { found = true; break; }
            p++;
        }
        if (!found) break;

        size_t ckPos = p;
        size_t startOffset = ckPos + 2;
        if (startOffset >= size) break;

        z_stream strm;
        memset(&strm, 0, sizeof(strm));
        strm.next_in = (Bytef*)(data + startOffset);
        strm.avail_in = (uInt)(size - startOffset);

        if (inflateInit2(&strm, -MAX_WBITS) != Z_OK) {
            // Can't even start a stream here — treat as a false-positive
            // "CK" match inside raw binary data and keep scanning.
            offset = ckPos + 1;
            continue;
        }

        if (!dict.empty()) {
            inflateSetDictionary(&strm, dict.data(), (uInt)dict.size());
        }

        std::vector<uint8_t> outBuf(33000); // one MSZIP block is at most 32768 bytes
        strm.next_out = outBuf.data();
        strm.avail_out = (uInt)outBuf.size();

        int ret = inflate(&strm, Z_FINISH);
        size_t totalOut = strm.total_out;
        size_t totalIn = strm.total_in;
        inflateEnd(&strm);

        if (ret == Z_STREAM_END && totalOut > 0) {
            outBuf.resize(totalOut);
            output.insert(output.end(), outBuf.begin(), outBuf.end());
            dict = outBuf; // becomes the preset dictionary for the next block
            offset = startOffset + totalIn;
            blockNum++;
        } else {
            // Coincidental "CK" byte pair inside non-header data — not a
            // real block boundary. Step forward one byte and keep looking.
            offset = ckPos + 1;
        }
    }

    snprintf(buf, sizeof(buf), "Total decompressed: %lu bytes across %d blocks\n",
             (unsigned long)output.size(), blockNum);
    xpkDebugLog() += buf;
    return output;
}

// Token parser
std::vector<XToken> XFileParser::parseTokens(const uint8_t* data, size_t size, int maxTokens) {
    std::vector<XToken> tokens;
    if (size < 4) return tokens;
    size_t offset = 0;
    int templateDepth = 0;
    int braceDepth = 0;
    int skipCount = 0;
    
    while (offset + 2 <= size && (int)tokens.size() < maxTokens) {
        uint16_t tokenType = readU16(data, offset);
        offset += 2;
        
        if (tokenType > 51) {
            skipCount++;
            if (skipCount > 1000) break;
            continue;
        }
        skipCount = 0;
        
        XToken token;
        token.type = tokenType;
        token.intValue = 0;
        token.floatValue = 0;
        token.dwordValue = 0;
        token.wordValue = 0;
        
        switch (tokenType) {
            case 1: {
                // NAME - no padding
                if (offset + 4 > size) { offset = size; break; }
                uint32_t len = readU32(data, offset);
                offset += 4;
                if (len > 10000 || offset + len > size) { offset = size; break; }
                token.name = std::string((const char*)(data + offset), len);
                offset += len;
                break;
            }
            case 2: {
                // STRING - 2 bytes padding after
                if (offset + 4 > size) { offset = size; break; }
                uint32_t len = readU32(data, offset);
                offset += 4;
                if (len > 10000 || offset + len > size) { offset = size; break; }
                token.name = std::string((const char*)(data + offset), len);
                offset += len;
                // STRING padding: 2 bytes null terminator
                if (offset + 2 <= size) offset += 2;
                break;
            }
            case 3:
                if (offset + 4 > size) { offset = size; break; }
                token.intValue = (int)readU32(data, offset);
                offset += 4;
                break;
            case 5:
                if (offset + 16 > size) { offset = size; break; }
                offset += 16;
                break;
            case 6: {
                if (offset + 4 > size) { offset = size; break; }
                uint32_t count = readU32(data, offset);
                offset += 4;
                if (count > 100000) { offset = size; break; }
                for (uint32_t i = 0; i < count && offset + 4 <= size; i++) {
                    token.intList.push_back((int)readU32(data, offset));
                    offset += 4;
                }
                break;
            }
            case 7: {
                if (offset + 4 > size) { offset = size; break; }
                uint32_t count = readU32(data, offset);
                offset += 4;
                if (count > 100000) { offset = size; break; }
                for (uint32_t i = 0; i < count && offset + 4 <= size; i++) {
                    uint32_t bits = readU32(data, offset);
                    float f; memcpy(&f, &bits, 4);
                    token.floatList.push_back(f);
                    offset += 4;
                }
                break;
            }
            case 10: braceDepth++; break;
            case 11:
                braceDepth--;
                if (braceDepth <= 0) { braceDepth = 0; templateDepth = 0; }
                break;
            case 12: case 13: case 14: case 15:
            case 16: case 17: case 18: case 19: case 20:
                break;
            case 31: templateDepth++; break;
            case 40:
                if (templateDepth == 0) {
                    if (offset + 2 > size) { offset = size; break; }
                    token.wordValue = readU16(data, offset); offset += 2;
                }
                break;
            case 41:
                if (templateDepth == 0) {
                    if (offset + 4 > size) { offset = size; break; }
                    token.dwordValue = (int)readU32(data, offset); offset += 4;
                }
                break;
            case 42:
                if (templateDepth == 0) {
                    if (offset + 4 > size) { offset = size; break; }
                    uint32_t bits = readU32(data, offset);
                    memcpy(&token.floatValue, &bits, 4);
                    offset += 4;
                }
                break;
            case 43:
                if (templateDepth == 0) {
                    if (offset + 8 > size) { offset = size; break; }
                    offset += 8;
                }
                break;
            case 44: case 45:
                if (templateDepth == 0) {
                    if (offset + 1 > size) { offset = size; break; }
                    offset += 1;
                }
                break;
            case 46:
                if (templateDepth == 0) {
                    if (offset + 2 > size) { offset = size; break; }
                    offset += 2;
                }
                break;
            case 47:
                if (templateDepth == 0) {
                    if (offset + 4 > size) { offset = size; break; }
                    offset += 4;
                }
                break;
            case 48: case 49: case 50:
                // LPSTR / UNICODE / CSTRING - no padding (per Assimp)
                if (templateDepth == 0) {
                    if (offset + 4 > size) { offset = size; break; }
                    uint32_t len = readU32(data, offset);
                    offset += 4;
                    if (len > 10000 || offset + len > size) { offset = size; break; }
                    offset += len;
                }
                break;
            case 51: break;
            default: break;
        }
        tokens.push_back(token);
    }
    return tokens;
}

std::string XFileParser::describeToken(const XToken& token) {
    std::ostringstream oss;
    switch (token.type) {
        case 1: oss << "NAME: \"" << token.name << "\""; break;
        case 2: oss << "STR: \"" << token.name << "\""; break;
        case 3: oss << "INT: " << token.intValue; break;
        case 5: oss << "GUID"; break;
        case 6: oss << "ILIST(" << token.intList.size() << ")"; break;
        case 7: oss << "FLIST(" << token.floatList.size() << ")"; break;
        case 10: oss << "{"; break;
        case 11: oss << "}"; break;
        case 12: oss << "("; break;
        case 13: oss << ")"; break;
        case 14: oss << "["; break;
        case 15: oss << "]"; break;
        case 16: oss << "<"; break;
        case 17: oss << ">"; break;
        case 18: oss << "."; break;
        case 19: oss << ","; break;
        case 20: oss << ";"; break;
        case 31: oss << "TEMPLATE"; break;
        case 40: oss << "WORD"; break;
        case 41: oss << "DWORD"; break;
        case 42: oss << "FLOAT"; break;
        case 43: oss << "DOUBLE"; break;
        case 44: oss << "CHAR"; break;
        case 45: oss << "UCHAR"; break;
        case 46: oss << "SWORD"; break;
        case 47: oss << "SDWORD"; break;
        case 48: oss << "LPSTR"; break;
        case 49: oss << "UNICODE"; break;
        case 50: oss << "CSTRING"; break;
        case 51: oss << "ARRAY"; break;
        default: oss << "??(" << token.type << ")"; break;
    }
    return oss.str();
}
