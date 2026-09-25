#pragma once
#include <string>
#include <vector>
#include <fstream>
#include <cstdint>
#include <unordered_map>

struct XPKEntry {
    std::string filename;
    uint32_t offset;
    uint32_t size;
};

class AssetManager {
public:
    AssetManager() = default;
    ~AssetManager();

    bool loadXPK(const std::string& filepath);
    std::vector<uint8_t> getAssetData(const std::string& filename);
    std::vector<std::string> getAllFilenames();

    // Lookups are case-insensitive and accept '/' or '\\' as separator, because
    // data/elements.txt refers to files like "gfx\\Snow_Corner.X" while the
    // archive stores "gfx\\snow_corner.x" (24 of 101 catalog entries differ
    // only by case).
    bool hasAsset(const std::string& filename) const;
    static std::string normalizeKey(const std::string& filename);

private:
    std::ifstream xpkFile;
    std::unordered_map<std::string, XPKEntry> fileTable; // key = normalizeKey(filename)
    std::vector<std::string> orderedFilenames;
};
