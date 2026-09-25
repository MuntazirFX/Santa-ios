#include "AniParser.h"
#include "XFileParser.h"
#include <cstring>
#include <cstdio>

std::vector<uint8_t> AniParser::decompress(const uint8_t* data, size_t size) {
    // .ani data is stored raw (see AniParser.h) — nothing to decompress.
    return std::vector<uint8_t>(data, data + size);
}

std::vector<AniClip> AniParser::parse(const uint8_t* data, size_t size) {
    std::vector<AniClip> clips;
    
    if (size < 16) return clips;
    
    // TODO: decode clip / bone boundaries (see the verified layout notes in AniParser.h)
    
    printf("[AniParser] TODO: Parse %zu bytes\n", size);
    return clips;
}
