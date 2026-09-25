#pragma once
#include <cstdint>
#include <string>
#include <vector>

std::string& xpkDebugLog();

struct XToken {
    int type;
    std::string name;
    int intValue;
    std::vector<int> intList;
    std::vector<float> floatList;
    float floatValue;
    int dwordValue;
    int wordValue;
};

class XFileParser {
public:
    static std::vector<XToken> parseTokens(const uint8_t* data, size_t size, int maxTokens);
    static std::string describeToken(const XToken& token);
    static std::vector<uint8_t> decompressMSZip(const uint8_t* data, size_t size);
};
