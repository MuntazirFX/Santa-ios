// Standalone harness: reproduces GameEngine.mm's extractMeshFromAsset (mesh +
// skinning) logic in plain C++ so it can be run/measured against the real
// xmas.xpk without Xcode. Build:
//   g++ -std=c++17 -Isrc tools/test_skin.cpp src/AssetManager.cpp \
//       src/XFileParser.cpp -lz -o test_skin
//   ./test_skin assets/xmas.xpk gfx\\weihnachtsman_000.x
#include "AssetManager.h"
#include "XFileParser.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <unordered_map>
#include <cmath>
#include <algorithm>

struct Vec3 { float x, y, z; };
struct Mat4 {
    float m[4][4];
    static Mat4 identity() {
        Mat4 r{};
        for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) r.m[i][j] = (i == j) ? 1.0f : 0.0f;
        return r;
    }
    static Mat4 fromFloats16(const std::vector<float>& f) {
        Mat4 r{};
        for (int i = 0; i < 16; i++) r.m[i / 4][i % 4] = f[i];
        return r;
    }
};
static Mat4 mulMat(const Mat4& a, const Mat4& b) {
    Mat4 r{};
    for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) {
        float s = 0; for (int k = 0; k < 4; k++) s += a.m[i][k] * b.m[k][j];
        r.m[i][j] = s;
    }
    return r;
}
static Vec3 transformPoint(const Vec3& v, const Mat4& M) {
    float x = v.x*M.m[0][0] + v.y*M.m[1][0] + v.z*M.m[2][0] + M.m[3][0];
    float y = v.x*M.m[0][1] + v.y*M.m[1][1] + v.z*M.m[2][1] + M.m[3][1];
    float z = v.x*M.m[0][2] + v.y*M.m[1][2] + v.z*M.m[2][2] + M.m[3][2];
    float w = v.x*M.m[0][3] + v.y*M.m[1][3] + v.z*M.m[2][3] + M.m[3][3];
    if (std::fabs(w) > 1e-6f && std::fabs(w - 1.0f) > 1e-6f) { x /= w; y /= w; z /= w; }
    return { x, y, z };
}
static void printMat(const char* label, const Mat4& M) {
    printf("%s:\n", label);
    for (int i = 0; i < 4; i++) printf("  [%8.4f %8.4f %8.4f %8.4f]\n", M.m[i][0], M.m[i][1], M.m[i][2], M.m[i][3]);
}

static int g_fixMode = 0; // 0=none, 1=append 1.0, 2=repeat last weight, 3=repeat first weight

struct SkinWeightsData {
    std::string boneName;
    std::vector<int> vertexIndices;
    std::vector<float> weights;
    Mat4 offsetMatrix;
};

static Mat4 transpose(const Mat4& a) {
    Mat4 r{};
    for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) r.m[i][j] = a.m[j][i];
    return r;
}

// order: 0 = offset*boneWorld (current GameEngine.mm), 1 = boneWorld*offset,
// 2 = offset only (no boneWorld), 3 = boneWorld only (no offset),
// 4 = transpose(offset)*boneWorld, 5 = boneWorld*transpose(offset),
// 6 = offset*boneWorld then result also transposed for the point transform,
// 7 = offset*boneWorld but with meshWorld applied afterward too
static void runSkinTest(const std::vector<XToken>& tokens, int order, bool verbose) {
    std::unordered_map<std::string, Mat4> boneWorldTransforms;
    std::unordered_map<size_t, Mat4> meshWorldByToken;
    {
        std::vector<Mat4> worldStack; worldStack.push_back(Mat4::identity());
        std::vector<char> braceKind; std::vector<std::string> frameNameStack;
        std::string pendingFrameName = ""; bool pendingFrame = false;
        for (size_t i = 0; i < tokens.size(); i++) {
            const auto& tok = tokens[i];
            if (tok.type == 1 && tok.name == "Mesh" && !pendingFrame) meshWorldByToken[i] = worldStack.back();
            if (tok.type == 1 && tok.name == "Frame") { pendingFrame = true; continue; }
            if (pendingFrame && tok.type == 1) { pendingFrameName = tok.name; pendingFrame = false; continue; }
            if (tok.type == 10) {
                if (!pendingFrameName.empty()) { worldStack.push_back(worldStack.back()); braceKind.push_back('F'); frameNameStack.push_back(pendingFrameName); pendingFrameName = ""; }
                else { braceKind.push_back('O'); frameNameStack.push_back(""); }
                continue;
            }
            if (tok.type == 11) {
                if (!braceKind.empty()) {
                    char kind = braceKind.back(); braceKind.pop_back();
                    if (kind == 'F') {
                        if (!frameNameStack.empty() && !frameNameStack.back().empty()) boneWorldTransforms[frameNameStack.back()] = worldStack.back();
                        worldStack.pop_back();
                    }
                    if (!frameNameStack.empty()) frameNameStack.pop_back();
                }
                continue;
            }
            if (tok.type == 1 && tok.name == "FrameTransformMatrix") {
                for (size_t j = i + 1; j < std::min(tokens.size(), i + 6); j++) {
                    if (tokens[j].type == 7 && tokens[j].floatList.size() >= 16) {
                        Mat4 local = Mat4::fromFloats16(tokens[j].floatList);
                        Mat4 parentWorld = worldStack.back();
                        worldStack.back() = mulMat(local, parentWorld);
                        break;
                    }
                }
                continue;
            }
        }
    }

    if (verbose) {
        printf("Frames with world transforms: %zu\n", boneWorldTransforms.size());
        for (auto& kv : boneWorldTransforms) printf("  %s\n", kv.first.c_str());
    }

    for (size_t i = 0; i < tokens.size(); i++) {
        const auto& tok = tokens[i];
        if (tok.type != 1 || tok.name != "Mesh") continue;
        Mat4 meshWorld = Mat4::identity();
        { auto mw = meshWorldByToken.find(i); if (mw != meshWorldByToken.end()) meshWorld = mw->second; }

        int depth = 0; bool entered = false; size_t meshEndIdx = tokens.size();
        const std::vector<float>* meshVerts = nullptr;
        std::vector<SkinWeightsData> skins;

        for (size_t j = i + 1; j < tokens.size(); j++) {
            const auto& t = tokens[j];
            if (t.type == 10) { depth++; entered = true; continue; }
            if (t.type == 11) { depth--; if (entered && depth == 0) { meshEndIdx = j; break; } continue; }
            if (t.type == 7 && !meshVerts) { meshVerts = &t.floatList; continue; }
            if (t.type == 1 && t.name == "MeshTextureCoords") {
                int d2 = 0; bool e2 = false;
                for (size_t k = j + 1; k < tokens.size(); k++) {
                    if (tokens[k].type == 10) { d2++; e2 = true; continue; }
                    if (tokens[k].type == 11) { d2--; if (e2 && d2 == 0) { j = k; break; } continue; }
                }
                continue;
            }
            if (t.type == 1 && t.name == "SkinWeights") {
                SkinWeightsData sw; std::vector<float> rawWeights;
                int d2 = 0; bool e2 = false; int state = 0;
                for (size_t k = j + 1; k < tokens.size(); k++) {
                    const auto& tt = tokens[k];
                    if (tt.type == 10) { d2++; e2 = true; continue; }
                    if (tt.type == 11) { d2--; if (e2 && d2 == 0) { j = k; break; } continue; }
                    if (state == 0) { if (tt.type == 2) { sw.boneName = tt.name; state = 1; } }
                    else if (state == 1) { if (tt.type == 6) { for (int v : tt.intList) sw.vertexIndices.push_back(v); state = 2; } }
                    else if (state == 2) { if (tt.type == 7) { rawWeights = tt.floatList; state = 3; } }
                }
                if (rawWeights.size() >= 16) {
                    size_t weightsLen = rawWeights.size() - 16;
                    sw.offsetMatrix = Mat4::fromFloats16(std::vector<float>(rawWeights.end() - 16, rawWeights.end()));
                    weightsLen = std::min(weightsLen, sw.vertexIndices.size());
                    sw.weights.assign(rawWeights.begin(), rawWeights.begin() + weightsLen);
                    if (g_fixMode == 1) { while (sw.weights.size() < sw.vertexIndices.size()) sw.weights.push_back(1.0f); }
                    else if (g_fixMode == 2) { while (sw.weights.size() < sw.vertexIndices.size()) sw.weights.push_back(sw.weights.back()); }
                    else if (g_fixMode == 3) { while (sw.weights.size() < sw.vertexIndices.size()) sw.weights.push_back(sw.weights.front()); }
                }
                if (!sw.boneName.empty() && !sw.vertexIndices.empty() && !sw.weights.empty()) skins.push_back(sw);
                continue;
            }
        }

        if (!meshVerts || meshVerts->size() < 3) continue;
        int vc = (int)(meshVerts->size() / 3);
        std::vector<Vec3> localVerts(vc);
        for (int v = 0; v < vc; v++) localVerts[v] = { (*meshVerts)[v*3], (*meshVerts)[v*3+1], (*meshVerts)[v*3+2] };

        printf("\n--- Mesh at token %zu: %d verts, %zu skin blocks, meshWorld ---\n", i, vc, skins.size());
        if (verbose) printMat("meshWorld", meshWorld);
        // How many times is each vertex referenced across ALL skin blocks, and
        // with what weight? (checks for duplicate/overlapping bone claims)
        std::vector<int> refCount(vc, 0);
        std::vector<float> refWeightSum(vc, 0.0f);
        for (auto& s : skins) {
            bool found = boneWorldTransforms.count(s.boneName) > 0;
            printf("  bone '%-20s' vertIdx=%-5zu weights=%-5zu found=%s\n", s.boneName.c_str(), s.vertexIndices.size(), s.weights.size(), found ? "yes" : "NO");
            for (size_t k = 0; k < s.vertexIndices.size() && k < s.weights.size(); k++) {
                int vi = s.vertexIndices[k];
                if (vi >= 0 && vi < vc) { refCount[vi]++; refWeightSum[vi] += s.weights[k]; }
            }
        }
        int maxRef=0; for (int v=0; v<vc; v++) maxRef = std::max(maxRef, refCount[v]);
        printf("  max times a single vertex is claimed by different bones: %d\n", maxRef);
        // print a few example vertices with weight sum far above 1
        int shown=0;
        for (int v=0; v<vc && shown<5; v++) if (refWeightSum[v] > 1.5f) { printf("    vertex %d: claimed by %d bones, weight sum=%.3f\n", v, refCount[v], refWeightSum[v]); shown++; }

        std::vector<Vec3> skinned(vc, {0,0,0});
        std::vector<float> weightSum(vc, 0.0f);
        for (const auto& skin : skins) {
            auto it = boneWorldTransforms.find(skin.boneName);
            if (it == boneWorldTransforms.end()) continue;
            Mat4 boneMatrix;
            if (order == 0) boneMatrix = mulMat(skin.offsetMatrix, it->second);
            else if (order == 1) boneMatrix = mulMat(it->second, skin.offsetMatrix);
            else if (order == 2) boneMatrix = skin.offsetMatrix;
            else if (order == 3) boneMatrix = it->second;
            else if (order == 4) boneMatrix = mulMat(transpose(skin.offsetMatrix), it->second);
            else if (order == 5) boneMatrix = mulMat(it->second, transpose(skin.offsetMatrix));
            else if (order == 7) boneMatrix = mulMat(mulMat(skin.offsetMatrix, it->second), meshWorld);
            else boneMatrix = it->second;
            for (size_t k = 0; k < skin.vertexIndices.size() && k < skin.weights.size(); k++) {
                int vi = skin.vertexIndices[k]; float w = skin.weights[k];
                if (vi < 0 || vi >= vc) continue;
                Vec3 t = transformPoint(localVerts[vi], boneMatrix);
                skinned[vi].x += w*t.x; skinned[vi].y += w*t.y; skinned[vi].z += w*t.z;
                weightSum[vi] += w;
            }
        }
        Vec3 mn{1e9f,1e9f,1e9f}, mx{-1e9f,-1e9f,-1e9f}, mnb{1e9f,1e9f,1e9f}, mxb{-1e9f,-1e9f,-1e9f};
        int unweighted = 0;
        double sumAbsDiff = 0; double sumSq = 0;
        for (int v = 0; v < vc; v++) {
            if (weightSum[v] < 1e-6f) { unweighted++; skinned[v] = transformPoint(localVerts[v], meshWorld); }
            else if (std::fabs(weightSum[v]-1.0f) > 1e-3f) { float inv=1.0f/weightSum[v]; skinned[v].x*=inv; skinned[v].y*=inv; skinned[v].z*=inv; }
            mn.x=std::min(mn.x,skinned[v].x); mn.y=std::min(mn.y,skinned[v].y); mn.z=std::min(mn.z,skinned[v].z);
            mx.x=std::max(mx.x,skinned[v].x); mx.y=std::max(mx.y,skinned[v].y); mx.z=std::max(mx.z,skinned[v].z);
            Vec3 bp = transformPoint(localVerts[v], meshWorld);
            mnb.x=std::min(mnb.x,bp.x); mnb.y=std::min(mnb.y,bp.y); mnb.z=std::min(mnb.z,bp.z);
            mxb.x=std::max(mxb.x,bp.x); mxb.y=std::max(mxb.y,bp.y); mxb.z=std::max(mxb.z,bp.z);
            double dx=skinned[v].x-bp.x, dy=skinned[v].y-bp.y, dz=skinned[v].z-bp.z;
            double d = std::sqrt(dx*dx+dy*dy+dz*dz);
            sumAbsDiff += d; sumSq += d*d;
        }
        int wOff=0; float minWS=1e9f,maxWS=-1e9f; double wsum=0;
        for (int v=0; v<vc; v++){ if(weightSum[v]<1e-6f) continue; minWS=std::min(minWS,weightSum[v]); maxWS=std::max(maxWS,weightSum[v]); wsum+=weightSum[v]; if(std::fabs(weightSum[v]-1.0f)>0.05f) wOff++; }
        printf("  weightSum stats (weighted verts only): min=%.4f max=%.4f avg=%.4f  far-from-1(>0.05): %d\n", minWS,maxWS,wsum/(vc-unweighted),wOff);
        printf("  unweighted verts: %d/%d\n", unweighted, vc);
        printf("  SKINNED  box: X[%.2f,%.2f] Y[%.2f,%.2f] Z[%.2f,%.2f]\n", mn.x,mx.x,mn.y,mx.y,mn.z,mx.z);
        printf("  BINDPOSE box: X[%.2f,%.2f] Y[%.2f,%.2f] Z[%.2f,%.2f]\n", mnb.x,mxb.x,mnb.y,mxb.y,mnb.z,mxb.z);
        printf("  per-vertex distance skinned-vs-bindpose: mean=%.4f  rms=%.4f  (0 = perfect rest-pose match)\n",
               sumAbsDiff/vc, std::sqrt(sumSq/vc));
    }
}

static void dumpTokensNear(const std::vector<XToken>& tokens, const std::string& needle, int context) {
    for (size_t i = 0; i < tokens.size(); i++) {
        if (tokens[i].type == 2 && tokens[i].name == needle) {
            size_t start = (i > 3) ? i - 3 : 0;
            size_t end = std::min(tokens.size(), i + context);
            printf("=== tokens around STRING \"%s\" (index %zu) ===\n", needle.c_str(), i);
            for (size_t k = start; k < end; k++) {
                printf("  [%zu] %s", k, XFileParser::describeToken(tokens[k]).c_str());
                if (tokens[k].type == 6) printf("  intList(%zu): ", tokens[k].intList.size());
                if (tokens[k].type == 7) printf("  floatList(%zu): ", tokens[k].floatList.size());
                if (tokens[k].type == 6 && tokens[k].intList.size() <= 20) { for (int v : tokens[k].intList) printf("%d ", v); }
                if (tokens[k].type == 7 && tokens[k].floatList.size() <= 20) { for (float v : tokens[k].floatList) printf("%.3f ", v); }
                printf("\n");
            }
            return;
        }
    }
    printf("STRING \"%s\" not found\n", needle.c_str());
}

// Same as XFileParser::parseTokens but also records each token's starting
// byte offset, so we can print raw hex around a token of interest and check
// the tokenizer against the actual bytes by hand.
struct DTok { XToken tok; size_t startOffset; };
static uint32_t rU32(const uint8_t* d, size_t o) { return d[o]|(d[o+1]<<8)|(d[o+2]<<16)|(d[o+3]<<24); }
static uint16_t rU16(const uint8_t* d, size_t o) { return d[o]|(d[o+1]<<8); }
static std::vector<DTok> parseTokensDebug(const uint8_t* data, size_t size, int maxTokens) {
    std::vector<DTok> tokens;
    size_t offset = 0; int templateDepth=0, braceDepth=0, skipCount=0;
    while (offset + 2 <= size && (int)tokens.size() < maxTokens) {
        size_t tokStart = offset;
        uint16_t tokenType = rU16(data, offset); offset += 2;
        if (tokenType > 51) { skipCount++; if (skipCount>1000) break; continue; }
        skipCount = 0;
        XToken token; token.type = tokenType; token.intValue=0; token.floatValue=0; token.dwordValue=0; token.wordValue=0;
        switch (tokenType) {
            case 1: { if(offset+4>size){offset=size;break;} uint32_t len=rU32(data,offset); offset+=4; if(len>10000||offset+len>size){offset=size;break;} token.name=std::string((const char*)(data+offset),len); offset+=len; break; }
            case 2: { if(offset+4>size){offset=size;break;} uint32_t len=rU32(data,offset); offset+=4; if(len>10000||offset+len>size){offset=size;break;} token.name=std::string((const char*)(data+offset),len); offset+=len; if(offset+2<=size) offset+=2; break; }
            case 3: if(offset+4>size){offset=size;break;} token.intValue=(int)rU32(data,offset); offset+=4; break;
            case 5: if(offset+16>size){offset=size;break;} offset+=16; break;
            case 6: { if(offset+4>size){offset=size;break;} uint32_t count=rU32(data,offset); offset+=4; if(count>100000){offset=size;break;} for(uint32_t i=0;i<count&&offset+4<=size;i++){token.intList.push_back((int)rU32(data,offset)); offset+=4;} break; }
            case 7: { if(offset+4>size){offset=size;break;} uint32_t count=rU32(data,offset); offset+=4; if(count>100000){offset=size;break;} for(uint32_t i=0;i<count&&offset+4<=size;i++){uint32_t bits=rU32(data,offset); float f; memcpy(&f,&bits,4); token.floatList.push_back(f); offset+=4;} break; }
            case 10: braceDepth++; break;
            case 11: braceDepth--; if(braceDepth<=0){braceDepth=0;templateDepth=0;} break;
            case 12: case 13: case 14: case 15: case 16: case 17: case 18: case 19: case 20: break;
            case 31: templateDepth++; break;
            case 40: if(templateDepth==0){if(offset+2>size){offset=size;break;} token.wordValue=rU16(data,offset); offset+=2;} break;
            case 41: if(templateDepth==0){if(offset+4>size){offset=size;break;} token.dwordValue=(int)rU32(data,offset); offset+=4;} break;
            case 42: if(templateDepth==0){if(offset+4>size){offset=size;break;} uint32_t bits=rU32(data,offset); memcpy(&token.floatValue,&bits,4); offset+=4;} break;
            case 43: if(templateDepth==0){if(offset+8>size){offset=size;break;} offset+=8;} break;
            case 44: case 45: if(templateDepth==0){if(offset+1>size){offset=size;break;} offset+=1;} break;
            case 46: if(templateDepth==0){if(offset+2>size){offset=size;break;} offset+=2;} break;
            case 47: if(templateDepth==0){if(offset+4>size){offset=size;break;} offset+=4;} break;
            case 48: case 49: case 50: if(templateDepth==0){if(offset+4>size){offset=size;break;} uint32_t len=rU32(data,offset); offset+=4; if(len>10000||offset+len>size){offset=size;break;} offset+=len;} break;
            case 51: break;
            default: break;
        }
        tokens.push_back({token, tokStart});
    }
    return tokens;
}

static void hexDumpRaw(const std::vector<uint8_t>& data, size_t start, size_t len) {
    for (size_t i = 0; i < len; i++) {
        if (i % 16 == 0) printf("\n  %06zx: ", start+i);
        printf("%02x ", data[start+i]);
    }
    printf("\n");
}

static void rawByteCheck(const std::vector<uint8_t>& decompressed, const std::string& needle) {
    auto dtoks = parseTokensDebug(decompressed.data(), decompressed.size(), 500000);
    for (size_t i = 0; i < dtoks.size(); i++) {
        if (dtoks[i].tok.type == 2 && dtoks[i].tok.name == needle) {
            printf("=== raw bytes around STRING \"%s\" ===\n", needle.c_str());
            // print the STRING token itself, then next 2 tokens' raw byte ranges
            for (size_t k = i; k < std::min(dtoks.size(), i + 4); k++) {
                size_t s = dtoks[k].startOffset;
                size_t e = (k + 1 < dtoks.size()) ? dtoks[k+1].startOffset : decompressed.size();
                printf("\ntoken[%zu] type=%d (%s) bytes[%zu..%zu) len=%zu:", k, dtoks[k].tok.type,
                       XFileParser::describeToken(dtoks[k].tok).c_str(), s, e, e - s);
                hexDumpRaw(decompressed, s, std::min(e - s, (size_t)200));
            }
            return;
        }
    }
    printf("not found\n");
}

int main(int argc, char** argv) {
    if (argc < 3) { printf("usage: %s xmas.xpk gfx\\\\weihnachtsman_000.x [order 0-3 | dump BoneName]\n", argv[0]); return 1; }
    AssetManager am;
    if (!am.loadXPK(argv[1])) { printf("cannot open %s\n", argv[1]); return 1; }
    auto fileData = am.getAssetData(argv[2]);
    if (fileData.empty()) { printf("asset not found: %s\n", argv[2]); return 1; }
    auto decompressed = XFileParser::decompressMSZip(fileData.data(), fileData.size());
    printf("decompressed %zu bytes from %zu (compressed)\n", decompressed.size(), fileData.size());
    auto tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 500000);
    printf("parsed %zu tokens\n", tokens.size());
    if (argc > 3 && std::string(argv[3]) == "dump") {
        dumpTokensNear(tokens, argc > 4 ? argv[4] : "Knochen_Mund3", 25);
        return 0;
    }
    if (argc > 3 && std::string(argv[3]) == "rawbytes") {
        rawByteCheck(decompressed, argc > 4 ? argv[4] : "Knochen_Mund3");
        return 0;
    }
    int order = argc > 3 ? atoi(argv[3]) : 0;
    bool verbose = argc > 4;
    g_fixMode = argc > 5 ? atoi(argv[5]) : 0;
    runSkinTest(tokens, order, verbose);
    return 0;
}
