#include "LevelParser.h"
#include "ElementCatalog.h"
#include <cstring>
#include <cstdio>

LevelData LevelParser::parse(const uint8_t* data, size_t size) {
    LevelData result;
    result.count = 0;
    
    if (size < 4) return result;
    
    uint32_t count;
    memcpy(&count, data, 4);
    
    const size_t recordSize = 60;
    size_t expected = 4 + (size_t)count * recordSize;
    
    if (count == 0 || count > 100000 || expected != size) {
        printf("[LevelParser] Size mismatch: count=%u expected=%zu actual=%zu\n",
               count, expected, size);
        return result;
    }
    
    result.count = count;
    result.entities.reserve(count);
    
    size_t p = 4;
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t* rec = data + p;
        
        // ✅ Use RawLevelEntity
        RawLevelEntity e;
        
        size_t nameLen = 0;
        while (nameLen < 32 && rec[nameLen] != 0) nameLen++;
        e.name.assign((const char*)rec, nameLen);
        
        memcpy(&e.x, rec + 32, 4);
        memcpy(&e.y, rec + 36, 4);
        memcpy(&e.z, rec + 40, 4);
        memcpy(&e.rotX, rec + 44, 4);
        memcpy(&e.rotY, rec + 48, 4);
        memcpy(&e.rotZ, rec + 52, 4);
        memcpy(&e.variant, rec + 56, 4);
        
        result.entities.push_back(e);
        p += recordSize;
    }
    
    printf("[LevelParser] Parsed %u entities\n", count);
    return result;
}

std::string LevelParser::getEntityType(const std::string& name) {
    // The old name-substring guesses were wrong for many real names
    // (e.g. "PRESENT A", "EXTRA LIFE", "SAVEPOINT", "Plattform EXIT",
    // "TROLL ELEVATOR" were all mis-classified). The authoritative type is
    // the TYPE field of data/elements.txt — load it once with
    // ElementCatalog::shared().parse(text) at startup.
    const ElementDef* def = ElementCatalog::shared().find(name);
    return def ? def->type : std::string("UNKNOWN");
}
