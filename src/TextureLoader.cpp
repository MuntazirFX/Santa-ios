#include "TextureLoader.h"
#include <cstring>
#include <algorithm>
#include <cctype>

namespace TextureLoader {

namespace {

uint32_t readU32(const uint8_t* d) {
    return (uint32_t)d[0] | ((uint32_t)d[1] << 8) | ((uint32_t)d[2] << 16) | ((uint32_t)d[3] << 24);
}

int shiftForMask(uint32_t mask) {
    if (mask == 0) return 0;
    int shift = 0;
    while ((mask & 1u) == 0u) { mask >>= 1; shift++; }
    return shift;
}

int bitsInMask(uint32_t mask) {
    int bits = 0;
    while (mask) { bits += (mask & 1u); mask >>= 1; }
    return bits;
}

uint8_t scaleToByte(uint32_t value, int bits) {
    if (bits <= 0) return 0;
    if (bits >= 8) return (uint8_t)(value >> (bits - 8));
    uint32_t maxVal = (1u << bits) - 1u;
    return (uint8_t)((value * 255u) / maxVal);
}

} // namespace

bool decodeDDS(const std::vector<uint8_t>& fileData,
               std::vector<uint8_t>& outRGBA8,
               int& outWidth,
               int& outHeight) {
    if (fileData.size() < 128) return false;
    const uint8_t* d = fileData.data();

    if (!(d[0] == 'D' && d[1] == 'D' && d[2] == 'S' && d[3] == ' ')) return false;

    uint32_t height = readU32(d + 12);
    uint32_t width  = readU32(d + 16);
    if (width == 0 || height == 0 || width > 8192 || height > 8192) return false;

    uint32_t pfFlags   = readU32(d + 80);
    uint32_t fourCC    = readU32(d + 84);
    uint32_t rgbCount  = readU32(d + 88);
    uint32_t rMask     = readU32(d + 92);
    uint32_t gMask     = readU32(d + 96);
    uint32_t bMask     = readU32(d + 100);
    uint32_t aMask     = readU32(d + 104);

    const uint32_t DDPF_ALPHAPIXELS = 0x1;
    const uint32_t DDPF_FOURCC      = 0x4;
    const uint32_t DDPF_RGB         = 0x40;

    const uint32_t DDPF_PALETTEINDEXED8 = 0x20;

    if (pfFlags & DDPF_FOURCC) {
        (void)fourCC;
        return false;
    }

    // ---- 8-bit palettized (e.g. himmel.dds): 256 x {R,G,B,flags} palette
    //      right after the 128-byte header, then width*height indices. ----
    if ((pfFlags & DDPF_PALETTEINDEXED8) && rgbCount == 8) {
        const size_t palOff = 128;
        const size_t idxOff = palOff + 256 * 4;
        if (fileData.size() < idxOff + (size_t)width * height) return false;
        outWidth = (int)width;
        outHeight = (int)height;
        outRGBA8.assign((size_t)width * height * 4, 0);
        const uint8_t* pal = d + palOff;
        const uint8_t* idx = d + idxOff;
        for (size_t i = 0; i < (size_t)width * height; i++) {
            const uint8_t* e = pal + (size_t)idx[i] * 4;
            uint8_t* o = outRGBA8.data() + i * 4;
            o[0] = e[0]; o[1] = e[1]; o[2] = e[2]; o[3] = 255;
        }
        return true;
    }

    if (!(pfFlags & DDPF_RGB)) return false;
    if (rgbCount != 16 && rgbCount != 24 && rgbCount != 32) return false;

    bool hasAlpha = (pfFlags & DDPF_ALPHAPIXELS) && aMask != 0;
    int bytesPerPixel = (int)(rgbCount / 8);

    int rShift = shiftForMask(rMask), rBits = bitsInMask(rMask);
    int gShift = shiftForMask(gMask), gBits = bitsInMask(gMask);
    int bShift = shiftForMask(bMask), bBits = bitsInMask(bMask);
    int aShift = shiftForMask(aMask), aBits = bitsInMask(aMask);

    size_t pixelDataOffset = 128;
    size_t rowBytes = (size_t)width * bytesPerPixel;
    size_t neededBytes = rowBytes * height;
    if (pixelDataOffset + neededBytes > fileData.size()) return false;

    outWidth = (int)width;
    outHeight = (int)height;
    outRGBA8.assign((size_t)width * height * 4, 0);

    const uint8_t* src = d + pixelDataOffset;
    for (uint32_t y = 0; y < height; y++) {
        const uint8_t* row = src + (size_t)y * rowBytes;
        uint8_t* outRow = outRGBA8.data() + (size_t)y * width * 4;
        for (uint32_t x = 0; x < width; x++) {
            uint32_t pixel = 0;
            const uint8_t* px = row + (size_t)x * bytesPerPixel;
            for (int b = 0; b < bytesPerPixel; b++) pixel |= ((uint32_t)px[b]) << (8 * b);

            uint8_t r = scaleToByte((pixel & rMask) >> rShift, rBits);
            uint8_t g = scaleToByte((pixel & gMask) >> gShift, gBits);
            uint8_t b8 = scaleToByte((pixel & bMask) >> bShift, bBits);
            uint8_t a = hasAlpha ? scaleToByte((pixel & aMask) >> aShift, aBits) : 255;

            uint8_t* o = outRow + (size_t)x * 4;
            o[0] = r; o[1] = g; o[2] = b8; o[3] = a;
        }
    }
    return true;
}

bool decodeTGA(const std::vector<uint8_t>& fileData,
               std::vector<uint8_t>& outRGBA8,
               int& outWidth,
               int& outHeight) {
    if (fileData.size() < 18) return false;
    const uint8_t* d = fileData.data();
    uint8_t idLen = d[0];
    uint8_t colorMapType = d[1];
    uint8_t imageType = d[2];
    if (colorMapType != 0 || imageType != 2) return false;   // only uncompressed truecolor
    uint32_t width  = d[12] | (d[13] << 8);
    uint32_t height = d[14] | (d[15] << 8);
    uint8_t bpp = d[16];
    uint8_t desc = d[17];
    if (width == 0 || height == 0 || width > 8192 || height > 8192) return false;
    if (bpp != 24 && bpp != 32) return false;
    size_t bytesPerPixel = bpp / 8;
    size_t dataOff = 18 + idLen;
    if (dataOff + (size_t)width * height * bytesPerPixel > fileData.size()) return false;

    bool topOrigin = (desc & 0x20) != 0;   // bit 5 set => rows already top-to-bottom
    outWidth = (int)width;
    outHeight = (int)height;
    outRGBA8.assign((size_t)width * height * 4, 255);
    for (uint32_t y = 0; y < height; y++) {
        uint32_t srcY = topOrigin ? y : (height - 1 - y);
        const uint8_t* row = d + dataOff + (size_t)srcY * width * bytesPerPixel;
        uint8_t* o = outRGBA8.data() + (size_t)y * width * 4;
        for (uint32_t x = 0; x < width; x++) {
            const uint8_t* px = row + (size_t)x * bytesPerPixel;   // stored B,G,R[,A]
            o[x * 4 + 0] = px[2];
            o[x * 4 + 1] = px[1];
            o[x * 4 + 2] = px[0];
            o[x * 4 + 3] = (bytesPerPixel == 4) ? px[3] : 255;
        }
    }
    return true;
}

bool decodeImage(const std::vector<uint8_t>& fileData,
                 std::vector<uint8_t>& outRGBA8,
                 int& outWidth,
                 int& outHeight) {
    if (fileData.size() >= 4 && fileData[0] == 'D' && fileData[1] == 'D' &&
        fileData[2] == 'S' && fileData[3] == ' ')
        return decodeDDS(fileData, outRGBA8, outWidth, outHeight);
    return decodeTGA(fileData, outRGBA8, outWidth, outHeight);
}

std::string resolveTextureXPKPath(const std::string& rawPath) {
    size_t slash = rawPath.find_last_of("\\/");
    std::string base = (slash == std::string::npos) ? rawPath : rawPath.substr(slash + 1);

    size_t dot = base.find_last_of('.');
    if (dot != std::string::npos) base = base.substr(0, dot);

    std::transform(base.begin(), base.end(), base.begin(),
                    [](unsigned char c) { return (char)std::tolower(c); });

    // ---- Names that differ between the .x files and the archive ----
    // (checked against all 88 .x files: 17 distinct texture references)
    if (base == "weihnachtsmann" || base == "santa") base = "nicolaus";
    else if (base == "troll" || base == "winter_troll") base = "wintertroll";
    else if (base == "crow") base = "rabe";
    else if (base == "snowman") base = "schneemann";
    else if (base == "plattform") base = "snow";
    else if (base == "dach") base = "dachpeter";          // dach.jpg  -> dachpeter.dds
    else if (base == "objects_old") base = "objects";     // objects_old.jpg -> objects.dds

    // The GUI sheets ship as 32-bit TGA, everything else as DDS.
    if (base == "gui2" || base == "gui_small" || base == "mouse" || base == "editgrid")
        return "maps\\" + base + ".tga";

    return "maps\\" + base + ".dds";
}

} // namespace TextureLoader
