#pragma once
#include <cstdint>
#include <vector>
#include <string>

// Minimal DDS / TGA decoder for the textures inside xmas.xpk.
//
// Formats actually present in the archive (all 22 .dds + 4 .tga checked):
//   RGB565   (0xF800/0x07E0/0x001F)          nicolaus, objects, haus2, misc ...
//   ARGB4444 (0xF000/0x0F00/0x00F0/0x000F)   fonts, effects, cdv, shadow, snow
//   ARGB1555 (0x8000/0x7C00/0x03E0/0x001F)   #tanne
//   ARGB8888                                  sc
//   P8       (8-bit palette, 256 x RGBX)      himmel (sky, 1024x1024)
//   TGA type 2, 32-bit BGRA                   gui2, gui_small, mouse, editgrid
// There is NO DXT/FOURCC compression anywhere. Only the base mip level is
// decoded, top-to-bottom row order. That matches Direct3D AND Metal, which
// both put V=0 at the TOP of the texture, so UVs from .x files must be
// used as-is (no "1 - v" flip).
namespace TextureLoader {

// Decodes a DDS file's base mip level into an RGBA8 (4 bytes/pixel) buffer.
// Supports uncompressed RGB/RGBA pixel formats of 16, 24, or 32 bits per
// pixel, deriving channel positions from the DDS_PIXELFORMAT bit masks.
// Also supports 8-bit palettized surfaces (DDPF_PALETTEINDEXED8).
// Compressed (FOURCC / DXT) formats are not supported and will fail.
// Returns true and fills outRGBA8/outWidth/outHeight on success.
bool decodeDDS(const std::vector<uint8_t>& fileData,
                std::vector<uint8_t>& outRGBA8,
                int& outWidth,
                int& outHeight);

// Decodes an uncompressed truecolor TGA (image type 2, 24 or 32 bpp) to RGBA8,
// top-to-bottom (honours the header's origin bit).
bool decodeTGA(const std::vector<uint8_t>& fileData,
               std::vector<uint8_t>& outRGBA8,
               int& outWidth,
               int& outHeight);

// Detects DDS vs TGA from the file contents and dispatches.
bool decodeImage(const std::vector<uint8_t>& fileData,
                 std::vector<uint8_t>& outRGBA8,
                 int& outWidth,
                 int& outHeight);

// Given a texture path as embedded in a DirectX .x file (e.g. an absolute
// Windows dev path like "D:\...\Weinachtsmann\Nicolaus.bmp"), resolves it
// to this archive's actual asset path, e.g. "maps\nicolaus.dds":
// strips the directory, drops the extension, lowercases, and rebuilds as
// "maps\\<name>.dds" — the convention this game's compiled asset pack uses.
std::string resolveTextureXPKPath(const std::string& rawPath);

} // namespace TextureLoader
