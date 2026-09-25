#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <iomanip>

void printHexDump(const std::vector<uint8_t>& data, size_t count) {
    for (size_t i = 0; i < data.size() && i < count; ++i) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << (int)data[i] << " ";
        if ((i + 1) % 16 == 0) std::cout << std::endl;
    }
    std::cout << std::dec << std::endl;
}

int main() {
    std::cout << "Santa iOS Engine - TGA to PPM Test" << std::endl;
    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }
    
    uint32_t tgaOffset = 5965124;
    file.seekg(tgaOffset, std::ios::beg);
    unsigned char header[18];
    file.read(reinterpret_cast<char*>(header), 18);
    
    uint8_t idLength = header[0];
    uint16_t width = header[12] | (header[13] << 8);
    uint16_t height = header[14] | (header[15] << 8);
    uint8_t bitsPerPixel = header[16];
    
    std::cout << "TGA Info: " << width << "x" << height << " | BPP: " << (int)bitsPerPixel << std::endl;
    
    uint32_t pixelDataStart = tgaOffset + 18 + idLength;
    file.seekg(pixelDataStart, std::ios::beg);
    
    int bytesPerPixel = bitsPerPixel / 8;
    int imageSize = width * height * bytesPerPixel;
    std::vector<uint8_t> pixels(imageSize);
    file.read(reinterpret_cast<char*>(pixels.data()), imageSize);
    file.close();
    
    std::cout << "Image Size: " << imageSize << " bytes" << std::endl;
    std::cout << "Pixel Data (First 32 bytes):" << std::endl;
    printHexDump(pixels, 32);
    
    std::ofstream ppmFile("test_output.ppm", std::ios::binary);
    if (!ppmFile.is_open()) {
        std::cerr << "Error: PPM file create nahi ho saki!" << std::endl;
        return 1;
    }
    
    ppmFile << "P6\n" << width << " " << height << "\n255\n";
    for (int i = 0; i < width * height; ++i) {
        uint8_t b = pixels[i * bytesPerPixel];
        uint8_t g = pixels[i * bytesPerPixel + 1];
        uint8_t r = pixels[i * bytesPerPixel + 2];
        ppmFile.write(reinterpret_cast<char*>(&r), 1);
        ppmFile.write(reinterpret_cast<char*>(&g), 1);
        ppmFile.write(reinterpret_cast<char*>(&b), 1);
    }
    ppmFile.close();
    
    std::ifstream check("test_output.ppm", std::ios::binary | std::ios::ate);
    std::cout << "PPM file size: " << check.tellg() << " bytes" << std::endl;
    check.close();
    
    std::cout << "test_output.ppm successfully ban gayi!" << std::endl;
    return 0;
}
