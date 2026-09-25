// Standalone harness: reproduces GameEngine.mm's extractMeshFromAsset (mesh +
// skinning) logic in plain C++ so it can be run/measured against the real
// xmas.xpk without Xcode. Build:
//   g++ -std=c++17 -Isrc tools/test_skin.cpp src/AssetManager.cpp \
//       src/XFileParser.cpp -lz -o test_skin
//   ./test_skin assets/xmas.xpk gfx\\weihnachtsman_000.x
#include "AssetManager.h"
#include "XFileParser.h"
#include <cstdio>
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

static bool g_fixTrailingWeight = false;

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
                    if (g_fixTrailingWeight && weightsLen + 1 == sw.vertexIndices.size()) {
                        sw.weights.assign(rawWeights.begin(), rawWeights.begin() + weightsLen);
                        sw.weights.push_back(1.0f); // implicit trailing full-weight vertex
                    } else {
                        weightsLen = std::min(weightsLen, sw.vertexIndices.size());
                        sw.weights.assign(rawWeights.begin(), rawWeights.begin() + weightsLen);
                    }
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
    int order = argc > 3 ? atoi(argv[3]) : 0;
    bool verbose = argc > 4;
    g_fixTrailingWeight = (argc > 5 && std::string(argv[5]) == "fixw");
    runSkinTest(tokens, order, verbose);
    return 0;
}
