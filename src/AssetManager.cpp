#include "AssetManager.h"
#include <iostream>
#include <algorithm>
#include <cctype>

AssetManager::~AssetManager() {
    if (xpkFile.is_open()) {
        xpkFile.close();
    }
}

// ============================================================
// xmas.xpk on-disk layout (verified against the actual file):
//
//   u32      count
//   u32[count]   nameOffsets      -> byte offset of each filename
//                                    *within the names blob below*
//   u32      namesLen             -> length of the names blob
//   u8[namesLen] namesBlob        -> NUL-terminated filenames,
//                                    indexed by nameOffsets[i]
//   u32      totalDataSize        -> sum of sizes[] (sanity value)
//   u32[count]   sizes            -> size in bytes of each file's data
//   u32[count]   fileTime         -> Unix timestamp of the file (all fall in
//                                    Sep-Nov 2002, verified)
//   u32[count]   dataOffset       -> ABSOLUTE offset of the file's data inside
//                                    the .xpk (verified == running sum for
//                                    all 177 entries)
//   ---- raw file data follows, back-to-back, in table order ----
//
// Files are stored back-to-back with NO per-file compression in this
// archive (despite occasional 0x1F 0x8B bytes appearing *inside* raw
// model data, which are not real gzip streams). We therefore just
// copy each entry's bytes out verbatim.
// ============================================================

bool AssetManager::loadXPK(const std::string& filepath) {
    if (xpkFile.is_open()) {
        xpkFile.close();
        xpkFile.clear();
    }

    xpkFile.open(filepath, std::ios::binary);
    if (!xpkFile.is_open()) {
        std::cerr << "[AssetManager] Failed to open XPK file: " << filepath << std::endl;
        return false;
    }

    fileTable.clear();
    orderedFilenames.clear();

    // ---- count ----
    uint32_t count = 0;
    xpkFile.read(reinterpret_cast<char*>(&count), sizeof(count));
    if (!xpkFile || count == 0 || count > 100000) {
        std::cerr << "[AssetManager] Invalid file count: " << count << std::endl;
        return false;
    }

    // ---- name offset table ----
    std::vector<uint32_t> nameOffsets(count);
    xpkFile.read(reinterpret_cast<char*>(nameOffsets.data()), count * sizeof(uint32_t));
    if (!xpkFile) {
        std::cerr << "[AssetManager] Failed reading name offset table" << std::endl;
        return false;
    }

    // ---- names blob ----
    uint32_t namesLen = 0;
    xpkFile.read(reinterpret_cast<char*>(&namesLen), sizeof(namesLen));
    if (!xpkFile || namesLen == 0 || namesLen > 50 * 1024 * 1024) {
        std::cerr << "[AssetManager] Invalid names blob length: " << namesLen << std::endl;
        return false;
    }

    std::vector<char> namesBlob(namesLen);
    xpkFile.read(namesBlob.data(), namesLen);
    if (!xpkFile) {
        std::cerr << "[AssetManager] Failed reading names blob" << std::endl;
        return false;
    }

    // ---- total data size (sanity check only) ----
    uint32_t totalDataSize = 0;
    xpkFile.read(reinterpret_cast<char*>(&totalDataSize), sizeof(totalDataSize));
    if (!xpkFile) {
        std::cerr << "[AssetManager] Failed reading total data size" << std::endl;
        return false;
    }

    // ---- per-file sizes ----
    std::vector<uint32_t> sizes(count);
    xpkFile.read(reinterpret_cast<char*>(sizes.data()), count * sizeof(uint32_t));
    if (!xpkFile) {
        std::cerr << "[AssetManager] Failed reading size table" << std::endl;
        return false;
    }

    // ---- per-file timestamps (unused) + per-file absolute data offsets ----
    std::vector<uint32_t> fileTimes(count);
    xpkFile.read(reinterpret_cast<char*>(fileTimes.data()), count * sizeof(uint32_t));
    std::vector<uint32_t> dataOffsets(count);
    xpkFile.read(reinterpret_cast<char*>(dataOffsets.data()), count * sizeof(uint32_t));
    if (!xpkFile) {
        std::cerr << "[AssetManager] Failed reading timestamp/offset tables" << std::endl;
        return false;
    }

    uint32_t dataStart = static_cast<uint32_t>(xpkFile.tellg());

    // ---- resolve filenames + build the file table ----
    uint32_t currentOffset = dataStart;
    uint32_t sumSizes = 0;
    for (uint32_t i = 0; i < count; ++i) {
        uint32_t nameOff = nameOffsets[i];
        std::string filename;
        if (nameOff < namesLen) {
            size_t p = nameOff;
            while (p < namesBlob.size() && namesBlob[p] != '\0') {
                filename += namesBlob[p];
                ++p;
            }
        }

        XPKEntry entry;
        entry.filename = filename;
        entry.size = sizes[i];
        // Prefer the offset stored in the archive; fall back to the running sum.
        entry.offset = (dataOffsets[i] >= dataStart) ? dataOffsets[i] : currentOffset;

        currentOffset += sizes[i];
        sumSizes += sizes[i];

        if (!filename.empty()) {
            orderedFilenames.push_back(filename);
            fileTable[normalizeKey(filename)] = entry;
        }
    }

    if (sumSizes != totalDataSize) {
        // Not fatal — just means our size-table assumption is slightly
        // off for this particular archive. Log it so it's visible in
        // device logs instead of silently mis-parsing.
        std::cerr << "[AssetManager] Warning: sum(sizes)=" << sumSizes
                   << " != totalDataSize=" << totalDataSize << std::endl;
    }

    std::cout << "[AssetManager] XPK loaded: " << fileTable.size()
               << " files, data starts at " << dataStart << std::endl;
    return true;
}

std::vector<uint8_t> AssetManager::getAssetData(const std::string& filename) {
    auto it = fileTable.find(normalizeKey(filename));
    if (it == fileTable.end()) {
        std::cerr << "[AssetManager] Asset not found: " << filename << std::endl;
        return {};
    }

    if (!xpkFile.is_open()) {
        std::cerr << "[AssetManager] getAssetData called with no XPK open" << std::endl;
        return {};
    }

    std::vector<uint8_t> data(it->second.size);
    xpkFile.clear(); // clear any eof/fail bits left over from a previous read
    xpkFile.seekg(it->second.offset, std::ios::beg);
    xpkFile.read(reinterpret_cast<char*>(data.data()), it->second.size);
    if (!xpkFile && !xpkFile.eof()) {
        std::cerr << "[AssetManager] Read failed for: " << filename << std::endl;
        return {};
    }
    return data;
}

std::vector<std::string> AssetManager::getAllFilenames() {
    return orderedFilenames;
}

std::string AssetManager::normalizeKey(const std::string& filename) {
    std::string k = filename;
    for (char& ch : k) {
        if (ch == '/') ch = '\\';
        else ch = (char)std::tolower((unsigned char)ch);
    }
    return k;
}

bool AssetManager::hasAsset(const std::string& filename) const {
    return fileTable.find(normalizeKey(filename)) != fileTable.end();
}
