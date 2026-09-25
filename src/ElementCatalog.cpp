#include "ElementCatalog.h"
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <sstream>

namespace {

std::string trim(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && std::isspace((unsigned char)s[a])) a++;
    while (b > a && std::isspace((unsigned char)s[b - 1])) b--;
    return s.substr(a, b - a);
}

std::string lower(std::string s) {
    for (char& c : s) c = (char)std::tolower((unsigned char)c);
    return s;
}

// Text between the first and last double quote ("" if none).
std::string quoted(const std::string& s) {
    size_t a = s.find('"');
    if (a == std::string::npos) return "";
    size_t b = s.find('"', a + 1);
    if (b == std::string::npos) return "";
    return s.substr(a + 1, b - a - 1);
}

} // namespace

size_t ElementCatalog::parse(const std::string& text) {
    defs_.clear();
    byName_.clear();
    byLower_.clear();

    std::istringstream in(text);
    std::string raw;
    ElementDef cur;
    bool have = false;

    auto flush = [&]() {
        if (!have) return;
        cur.meshFile = cur.file;
        size_t n = cur.meshFile.size();
        if (n >= 4 && lower(cur.meshFile.substr(n - 4)) == ".ani") {
            cur.aniFile = cur.file;
            cur.meshFile = cur.meshFile.substr(0, n - 4) + ".x";
        }
        size_t idx = defs_.size();
        defs_.push_back(cur);
        byName_[cur.name] = idx;                 // later duplicates overwrite earlier (same data)
        byLower_[lower(trim(cur.name))] = idx;
        have = false;
    };

    while (std::getline(in, raw)) {
        std::string line = trim(raw);           // also strips '\r'
        if (line.empty()) continue;

        size_t sp = line.find_first_of(" \t");
        std::string key = (sp == std::string::npos) ? line : line.substr(0, sp);
        std::string rest = (sp == std::string::npos) ? "" : trim(line.substr(sp));

        if (key == "ELEMENT") {
            flush();
            cur = ElementDef();
            cur.name = quoted(rest);
            have = true;
        } else if (!have) {
            continue;
        } else if (key == "FILE")           cur.file = quoted(rest);
        else if (key == "EFFECT")           cur.effect = quoted(rest);
        else if (key == "TYPE")             cur.type = rest;
        else if (key == "RADIUS")           cur.radius = (float)std::atof(rest.c_str());
        else if (key == "SCALING")          cur.scaling = (float)std::atof(rest.c_str());
        else if (key == "SPEED")            cur.speed = (float)std::atof(rest.c_str());
        else if (key == "JUMPHEIGHT")       cur.jumpHeight = (float)std::atof(rest.c_str());
        else if (key == "VERTICALOFFSET")   cur.verticalOffset = (float)std::atof(rest.c_str());
        else if (key == "FRICTION")         cur.friction = (float)std::atof(rest.c_str());
        else if (key == "ROTATION")         cur.rotation = (float)std::atof(rest.c_str());
        else if (key == "WALKANIM")         cur.walkAnim = std::atoi(rest.c_str());
    }
    flush();
    return defs_.size();
}

const ElementDef* ElementCatalog::find(const std::string& name) const {
    auto it = byName_.find(name);
    if (it != byName_.end()) return &defs_[it->second];
    auto it2 = byLower_.find(lower(trim(name)));
    if (it2 != byLower_.end()) return &defs_[it2->second];
    return nullptr;
}

ElementCatalog& ElementCatalog::shared() {
    static ElementCatalog instance;
    return instance;
}
