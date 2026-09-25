#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"
#include "TextureLoader.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>
#include <unordered_map>

// ============ Math Helpers ============
struct Vec3 { float x, y, z; };

struct Mat4 {
    float m[4][4];
    static Mat4 identity() {
        Mat4 r{};
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++)
                r.m[i][j] = (i == j) ? 1.0f : 0.0f;
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
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++) {
            float s = 0;
            for (int k = 0; k < 4; k++) s += a.m[i][k] * b.m[k][j];
            r.m[i][j] = s;
        }
    return r;
}

static Vec3 transformPoint(const Vec3& v, const Mat4& M) {
    float x = v.x*M.m[0][0] + v.y*M.m[1][0] + v.z*M.m[2][0] + M.m[3][0];
    float y = v.x*M.m[0][1] + v.y*M.m[1][1] + v.z*M.m[2][1] + M.m[3][1];
    float z = v.x*M.m[0][2] + v.y*M.m[1][2] + v.z*M.m[2][2] + M.m[3][2];
    float w = v.x*M.m[0][3] + v.y*M.m[1][3] + v.z*M.m[2][3] + M.m[3][3];
    if (std::fabs(w) > 1e-6f && std::fabs(w - 1.0f) > 1e-6f) {
        x /= w; y /= w; z /= w;
    }
    return { x, y, z };
}

struct SkinWeightsData {
    std::string boneName;
    std::vector<int> vertexIndices;
    std::vector<float> weights;
    Mat4 offsetMatrix;
};

@implementation MeshData
@end

@implementation LevelObject
@end

@implementation GameEngine

+ (NSData *)loadAssetNamed:(NSString *)name {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return nil;
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return nil;
    std::vector<uint8_t> d = am.getAssetData([name UTF8String]);
    if (d.empty()) return nil;
    return [NSData dataWithBytes:d.data() length:d.size()];
}

+ (NSString *)listLevelFiles {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return @"No XPK";
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return @"XPK load failed";
    std::vector<std::string> all = am.getAllFilenames();
    NSMutableString *out = [NSMutableString string];
    for (const auto& n : all) {
        if (n.find("levels\\") != std::string::npos || n.find("levels/") != std::string::npos) {
            [out appendFormat:@"%s\n", n.c_str()];
        }
    }
    return out;
}

+ (NSString *)listTextureFiles {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return @"No XPK";
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return @"XPK load failed";
    std::vector<std::string> all = am.getAllFilenames();
    NSMutableString *out = [NSMutableString string];
    for (const auto& n : all) {
        if (n.find("maps\\") != std::string::npos || n.find("maps/") != std::string::npos) {
            [out appendFormat:@"%s\n", n.c_str()];
        }
    }
    return out;
}

+ (MeshData *)extractMeshFromAsset:(NSString *)assetName {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return nil;
    
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return nil;
    
    std::string name = [assetName UTF8String];
    std::vector<uint8_t> fileData = am.getAssetData(name);
    if (fileData.empty()) return nil;
    
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(fileData.data(), fileData.size());
    if (decompressed.size() < 16) return nil;
    
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 500000);
    
    // ============================================================
    // PASS 1: Frame hierarchy → boneWorldTransforms map
    // ============================================================
    std::unordered_map<std::string, Mat4> boneWorldTransforms;
    // World matrix of the Frame that CONTAINS each Mesh (keyed by the index of
    // the "Mesh" token). Static models are authored with their pivot in the
    // frame's transform: e.g. Santa's mesh is centred on the origin and his
    // frame lifts it by +63.07 so the feet stand on y=0 — exactly the pose in
    // assets/weihnachtsman_000.obj. Platforms, trees, houses, hills ... all
    // rely on this too, so the transform must be applied to unskinned vertices.
    std::unordered_map<size_t, Mat4> meshWorldByToken;
    {
        std::vector<Mat4> worldStack;
        worldStack.push_back(Mat4::identity());
        std::vector<char> braceKind;
        std::vector<std::string> frameNameStack;
        std::string pendingFrameName = "";
        bool pendingFrame = false;
        
        for (size_t i = 0; i < tokens.size(); i++) {
            const auto& tok = tokens[i];
            
            if (tok.type == 1 && tok.name == "Mesh" && !pendingFrame) {
                meshWorldByToken[i] = worldStack.back();
            }
            
            if (tok.type == 1 && tok.name == "Frame") {
                pendingFrame = true;
                continue;
            }
            if (pendingFrame && tok.type == 1) {
                pendingFrameName = tok.name;
                pendingFrame = false;
                continue;
            }
            // BUG (fixed): if the token right after "Frame" isn't a NAME (type 1)
            // — e.g. the template-declarations section's `template Frame { <guid> ... }`,
            // where a brace comes next — `pendingFrame` stayed true and silently
            // grabbed the NEXT unrelated NAME token anywhere later in the file
            // (verified: it was mislabelling "FrameTransformMatrix" as a frame name
            // on the real weihnachtsman_000.x). Any non-NAME token means this
            // "Frame" wasn't followed by a name, so stop waiting for one.
            if (pendingFrame && tok.type != 1) {
                pendingFrame = false;
            }
            if (tok.type == 10) {
                if (!pendingFrameName.empty()) {
                    worldStack.push_back(worldStack.back());
                    braceKind.push_back('F');
                    frameNameStack.push_back(pendingFrameName);
                    pendingFrameName = "";
                } else {
                    braceKind.push_back('O');
                    frameNameStack.push_back("");
                }
                continue;
            }
            if (tok.type == 11) {
                if (!braceKind.empty()) {
                    char kind = braceKind.back();
                    braceKind.pop_back();
                    if (kind == 'F') {
                        if (!frameNameStack.empty() && !frameNameStack.back().empty()) {
                            boneWorldTransforms[frameNameStack.back()] = worldStack.back();
                        }
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
    
    // ============================================================
    // PASS 2: Extract Mesh + apply skinning
    // ============================================================
    std::vector<float> allVerts;
    std::vector<float> allUVs;
    std::vector<float> allColors;
    std::vector<uint32_t> allIdx;
    
    int meshCount = 0;
    int uvFoundCount = 0;
    int uvMissingCount = 0;
    int totalSkinBlocks = 0;
    int missingBoneCount = 0;
    std::string firstTextureFileName;
    
    for (size_t i = 0; i < tokens.size(); i++) {
        const auto& tok = tokens[i];
        if (tok.type != 1 || tok.name != "Mesh") continue;
        
        Mat4 meshWorld = Mat4::identity();
        {
            auto mw = meshWorldByToken.find(i);
            if (mw != meshWorldByToken.end()) meshWorld = mw->second;
        }
        
        int depth = 0;
        bool entered = false;
        int meshEndIdx = (int)tokens.size();
        const std::vector<float>* meshVerts = nullptr;
        const std::vector<int>* meshFaces = nullptr;
        const std::vector<float>* meshUVs = nullptr;
        std::vector<SkinWeightsData> skins;
        std::string textureFileName;
        
        for (size_t j = i + 1; j < tokens.size(); j++) {
            const auto& t = tokens[j];
            if (t.type == 10) { depth++; entered = true; continue; }
            if (t.type == 11) {
                depth--;
                if (entered && depth == 0) { meshEndIdx = (int)j; break; }
                continue;
            }
            
            if (t.type == 7 && !meshVerts) { meshVerts = &t.floatList; continue; }
            if (t.type == 6 && meshVerts && !meshFaces) { meshFaces = &t.intList; continue; }
            
            if (t.type == 1 && t.name == "TextureFilename" && textureFileName.empty()) {
                for (size_t k = j + 1; k < tokens.size() && k < j + 5; k++) {
                    if (tokens[k].type == 2 || tokens[k].type == 1 || tokens[k].type == 50) {
                        textureFileName = tokens[k].name;
                        break;
                    }
                }
                continue;
            }
            
            if (t.type == 1 && t.name == "MeshTextureCoords") {
                // BUG (fixed): this used to `break` the inner loop the moment it
                // found the FLOAT_LIST (type 7), setting j to that token's index
                // WITHOUT ever consuming MeshTextureCoords' own closing brace.
                // The very next token in the file is that closing "}" (type 11),
                // which the OUTER loop then saw and mistook for the Mesh's own
                // closing brace (outer `depth` was never incremented for this
                // inner "{", so one "}" brought it straight to 0) — ending the
                // Mesh scan right there. Anything that follows MeshTextureCoords
                // in the file — crucially SkinWeights — was silently never seen
                // for that mesh. Fix: keep scanning with d2/e2 all the way to
                // MeshTextureCoords' matching "}" before resuming the outer scan.
                int d2 = 0; bool e2 = false;
                for (size_t k = j + 1; k < tokens.size(); k++) {
                    if (tokens[k].type == 10) { d2++; e2 = true; continue; }
                    if (tokens[k].type == 11) {
                        d2--;
                        if (e2 && d2 == 0) { j = k; break; }
                        continue;
                    }
                    if (tokens[k].type == 7 && !meshUVs) { meshUVs = &tokens[k].floatList; }
                }
                continue;
            }
            
            if (t.type == 1 && t.name == "SkinWeights") {
                SkinWeightsData sw;
                std::vector<float> rawWeights;
                int d2 = 0; bool e2 = false;
                int state = 0; // 0=need name, 1=need vertex indices, 2=need weights+matrix blob
                
                for (size_t k = j + 1; k < tokens.size(); k++) {
                    const auto& tt = tokens[k];
                    
                    if (tt.type == 10) { d2++; e2 = true; continue; }
                    if (tt.type == 11) {
                        d2--;
                        if (e2 && d2 == 0) { j = k; break; }
                        continue;
                    }
                    
                    if (state == 0) {
                        if (tt.type == 2) { sw.boneName = tt.name; state = 1; }
                    } else if (state == 1) {
                        if (tt.type == 6) {
                            for (int v : tt.intList) sw.vertexIndices.push_back(v);
                            state = 2;
                        }
                    } else if (state == 2) {
                        if (tt.type == 7) {
                            rawWeights = tt.floatList;
                            state = 3;
                        }
                    }
                }
                
                // The float array after the vertex-index array packs the
                // per-vertex weights FIRST, followed by the bone's 4x4
                // offset matrix — the matrix is ALWAYS exactly the LAST 16
                // floats, regardless of how many weights precede it.
                if (rawWeights.size() >= 16) {
                    size_t weightsLen = rawWeights.size() - 16;
                    weightsLen = std::min(weightsLen, sw.vertexIndices.size());
                    sw.weights.assign(rawWeights.begin(), rawWeights.begin() + weightsLen);
                    sw.offsetMatrix = Mat4::fromFloats16(std::vector<float>(rawWeights.end() - 16, rawWeights.end()));
                } else if (!rawWeights.empty()) {
                    size_t nW = std::min(rawWeights.size(), sw.vertexIndices.size());
                    sw.weights.assign(rawWeights.begin(), rawWeights.begin() + nW);
                    sw.offsetMatrix = Mat4::identity();
                }
                
                if (!sw.boneName.empty() && !sw.vertexIndices.empty() && !sw.weights.empty()) {
                    skins.push_back(sw);
                    totalSkinBlocks++;
                }
                continue;
            }
        }
        
        if (meshVerts && meshVerts->size() >= 3) {
            int vc = (int)(meshVerts->size() / 3);
            int baseVertex = (int)(allVerts.size() / 3);
            
            std::vector<Vec3> localVerts(vc);
            for (int v = 0; v < vc; v++) {
                localVerts[v] = { (*meshVerts)[v*3], (*meshVerts)[v*3+1], (*meshVerts)[v*3+2] };
            }
            
            // ===== Apply skinning (blend each vertex by its contributing bones) =====
            std::vector<Vec3> skinned(vc, {0,0,0});
            std::vector<float> weightSum(vc, 0.0f);
            
            for (const auto& skin : skins) {
                auto it = boneWorldTransforms.find(skin.boneName);
                if (it == boneWorldTransforms.end()) {
                    missingBoneCount++;
                    continue;
                }
                Mat4 boneMatrix = mulMat(skin.offsetMatrix, it->second);
                for (size_t k = 0; k < skin.vertexIndices.size() && k < skin.weights.size(); k++) {
                    int vi = skin.vertexIndices[k];
                    float w = skin.weights[k];
                    if (vi < 0 || vi >= vc) continue;
                    Vec3 t = transformPoint(localVerts[vi], boneMatrix);
                    skinned[vi].x += w * t.x;
                    skinned[vi].y += w * t.y;
                    skinned[vi].z += w * t.z;
                    weightSum[vi] += w;
                }
            }
            for (int v = 0; v < vc; v++) {
                if (weightSum[v] < 1e-6f) {
                    // unweighted vertex: bind pose placed by its Frame's world matrix
                    skinned[v] = transformPoint(localVerts[v], meshWorld);
                } else if (std::fabs(weightSum[v] - 1.0f) > 1e-3f) {
                    float inv = 1.0f / weightSum[v];
                    skinned[v].x *= inv; skinned[v].y *= inv; skinned[v].z *= inv;
                }
            }
            
            for (int v = 0; v < vc; v++) {
                allVerts.push_back(skinned[v].x);
                allVerts.push_back(skinned[v].y);
                allVerts.push_back(skinned[v].z);
                allColors.push_back(1.0f);
                allColors.push_back(1.0f);
                allColors.push_back(1.0f);
            }
            
            // ===== Faces =====
            // Real layout (verified against actual data): the ILIST is
            // [nFaces header, then repeating (vertsInFace, idx0, idx1, ...)]
            // per face — NOT a flat stream of raw index triples. Skipping
            // the leading header is essential: without it, the header
            // value itself gets read as a vertex index, which for this
            // mesh (2016) is far outside the valid 0..vertexCount-1 range
            // and produces out-of-bounds GPU reads — the "exploded/spiky"
            // geometry symptom.
            if (meshFaces && !meshFaces->empty()) {
                const auto& raw = *meshFaces;
                size_t p = 1; // skip the nFaces header
                while (p < raw.size()) {
                    uint32_t cnt = raw[p++];
                    if (cnt < 3 || cnt > 16 || p + cnt > raw.size()) break;
                    for (uint32_t k = 1; k + 1 < cnt; k++) {
                        int i0 = raw[p], i1 = raw[p + k], i2 = raw[p + k + 1];
                        if (i0 < 0 || i0 >= vc || i1 < 0 || i1 >= vc || i2 < 0 || i2 >= vc) continue;
                        allIdx.push_back((uint32_t)i0 + baseVertex);
                        allIdx.push_back((uint32_t)i1 + baseVertex);
                        allIdx.push_back((uint32_t)i2 + baseVertex);
                    }
                    p += cnt;
                }
            }
            
            if (meshUVs && meshUVs->size() >= (size_t)vc * 2) {
                allUVs.insert(allUVs.end(), meshUVs->begin(), meshUVs->begin() + vc * 2);
                uvFoundCount++;
            } else {
                uvMissingCount++;
                for (int u = 0; u < vc; u++) {
                    allUVs.push_back(0.5f);
                    allUVs.push_back(0.5f);
                }
            }
            
            if (firstTextureFileName.empty() && !textureFileName.empty()) {
                firstTextureFileName = textureFileName;
            }
            meshCount++;
        }
        i = meshEndIdx;
    }
    
    // The .x files reference their material by name INSIDE the Mesh, while the
    // Material { TextureFilename { "..." } } block itself sits OUTSIDE the Mesh
    // braces — so the per-mesh scan above finds nothing. (That is why only
    // Santa had a texture, via the hard-coded fallback below, and every level
    // model rendered white.) Fall back to the first non-empty TextureFilename
    // anywhere in the file (hill01.x has an empty one first, hence the loop).
    if (firstTextureFileName.empty()) {
        for (size_t i = 0; i < tokens.size() && firstTextureFileName.empty(); i++) {
            if (tokens[i].type != 1 || tokens[i].name != "TextureFilename") continue;
            for (size_t k = i + 1; k < tokens.size() && k < i + 5; k++) {
                if ((tokens[k].type == 2 || tokens[k].type == 50) && !tokens[k].name.empty()) {
                    firstTextureFileName = tokens[k].name;
                    break;
                }
            }
        }
    }
    
    if (firstTextureFileName.empty() && [assetName containsString:@"weihnachtsman"]) {
        firstTextureFileName = "Nicolaus.bmp";
    }
    
    if (allVerts.empty() || allIdx.empty()) return nil;
    
    MeshData *mesh = [[MeshData alloc] init];
    mesh.vertexCount = (int)(allVerts.size() / 3);
    mesh.faceCount = (int)(allIdx.size() / 3);
    mesh.vertices = [NSMutableData dataWithBytes:allVerts.data() length:allVerts.size() * 4];
    mesh.indices = [NSMutableData dataWithBytes:allIdx.data() length:allIdx.size() * sizeof(uint32_t)];
    mesh.uvs = [NSMutableData dataWithBytes:allUVs.data() length:allUVs.size() * 4];
    mesh.colors = [NSMutableData dataWithBytes:allColors.data() length:allColors.size() * 4];
    mesh.offset = 0;
    
    NSString *textureInfo = @"no texture";
    if (!firstTextureFileName.empty()) {
        std::string xpkPath = TextureLoader::resolveTextureXPKPath(firstTextureFileName);
        mesh.textureName = [NSString stringWithUTF8String:xpkPath.c_str()];
        textureInfo = mesh.textureName;
    }
    
    NSString *uvStatus = [NSString stringWithFormat:@"UVs: %d OK, %d MISS", uvFoundCount, uvMissingCount];
    mesh.debugInfo = [NSString stringWithFormat:
                      @"%@\n%dM %dSK %dMiss\n%d v, %d f\n%@\ntex: %@",
                      assetName, meshCount, totalSkinBlocks, missingBoneCount,
                      mesh.vertexCount, mesh.faceCount, uvStatus, textureInfo];
    return mesh;
}

+ (NSData *)loadTextureRGBA8Named:(NSString *)xpkPath width:(int *)outWidth height:(int *)outHeight {
    if (!xpkPath) return nil;
    NSData *fileData = [self loadAssetNamed:xpkPath];
    if (!fileData || fileData.length == 0) return nil;
    std::vector<uint8_t> raw((const uint8_t *)fileData.bytes, (const uint8_t *)fileData.bytes + fileData.length);
    std::vector<uint8_t> rgba;
    int w = 0, h = 0;
    if (!TextureLoader::decodeImage(raw, rgba, w, h)) return nil;   // DDS (RGB565/ARGB4444/1555/8888/P8) or TGA
    if (outWidth) *outWidth = w;
    if (outHeight) *outHeight = h;
    return [NSData dataWithBytes:rgba.data() length:rgba.size()];
}

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)loadElementCatalog {
    // Parses data/elements.txt: repeating blocks of
    //   ELEMENT   "Name"
    //   FILE      "gfx\...x"
    //   ... other KEY value lines ...
    //   TYPE      ENEMY|RECTFORM|PLATTFORM|DECO|BONUS|EXIT|JUMPER|ELEVATOR|...
    // Returns name -> [meshFile, elementType] (either may be empty if absent).
    NSData *data = [self loadAssetNamed:@"data\\elements.txt"];
    if (!data) return @{};
    
    NSString *text = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!text) return @{};
    
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *catalog = [NSMutableDictionary dictionary];
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    NSString *currentName = nil;
    NSString *currentFile = @"";
    NSString *currentType = @"";
    
    NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:ws];
        if (line.length == 0) continue;
        
        if ([line hasPrefix:@"ELEMENT"]) {
            // Flush previous element into the catalog before starting a new one.
            if (currentName) catalog[currentName] = @[currentFile, currentType];
            currentFile = @""; currentType = @"";
            
            NSRange q1 = [line rangeOfString:@"\""];
            if (q1.location != NSNotFound) {
                NSRange q2 = [line rangeOfString:@"\"" options:0 range:NSMakeRange(q1.location + 1, line.length - q1.location - 1)];
                if (q2.location != NSNotFound) {
                    currentName = [line substringWithRange:NSMakeRange(q1.location + 1, q2.location - q1.location - 1)];
                } else {
                    currentName = nil;
                }
            } else {
                currentName = nil;
            }
        } else if ([line hasPrefix:@"FILE"]) {
            NSRange q1 = [line rangeOfString:@"\""];
            if (q1.location != NSNotFound) {
                NSRange q2 = [line rangeOfString:@"\"" options:0 range:NSMakeRange(q1.location + 1, line.length - q1.location - 1)];
                if (q2.location != NSNotFound) {
                    currentFile = [line substringWithRange:NSMakeRange(q1.location + 1, q2.location - q1.location - 1)];
                }
            }
        } else if ([line hasPrefix:@"TYPE"]) {
            NSString *rest = [line substringFromIndex:4];
            currentType = [rest stringByTrimmingCharactersInSet:ws];
        }
    }
    if (currentName) catalog[currentName] = @[currentFile, currentType];
    
    return catalog;
}

+ (NSArray<LevelObject *> *)parseLevelData:(NSString *)levelPath {
    // Verified binary layout (matches every level file in the archive):
    //   u32 count
    //   count records of 60 bytes each:
    //     char name[32]     — NUL-terminated, padded with 0xCD filler
    //     float x, y, z     — world position
    //     float e1, e2, e3  — second float triplet (rotation or a linked
    //                         point for movers/elevators — exact per-type
    //                         meaning not yet confirmed at runtime)
    //     int32 variant
    NSData *data = [self loadAssetNamed:levelPath];
    if (!data || data.length < 4) return @[];
    
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger totalSize = data.length;
    
    uint32_t count;
    memcpy(&count, bytes, 4);
    
    const NSUInteger recordSize = 60;
    NSUInteger expected = 4 + (NSUInteger)count * recordSize;
    if (count == 0 || count > 100000 || expected != totalSize) {
        // Doesn't match the verified format — bail out rather than guess.
        return @[];
    }
    
    NSDictionary<NSString *, NSArray<NSString *> *> *catalog = [self loadElementCatalog];
    NSMutableArray<LevelObject *> *objects = [NSMutableArray arrayWithCapacity:count];
    
    NSUInteger p = 4;
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *rec = bytes + p;
        
        // Name: NUL-terminated within the 32-byte field.
        size_t nameLen = 0;
        while (nameLen < 32 && rec[nameLen] != 0) nameLen++;
        NSString *name = [[NSString alloc] initWithBytes:rec length:nameLen encoding:NSASCIIStringEncoding];
        if (!name) name = @"";
        
        float f[6];
        memcpy(f, rec + 32, sizeof(f));
        int32_t variant;
        memcpy(&variant, rec + 56, 4);
        
        LevelObject *obj = [[LevelObject alloc] init];
        obj.objectName = name;
        obj.x = f[0]; obj.y = f[1]; obj.z = f[2];
        obj.extra1 = f[3]; obj.extra2 = f[4]; obj.extra3 = f[5];
        obj.variant = variant;
        
        NSArray<NSString *> *info = catalog[name];
        if (info) {
            NSString *file = info[0];
            // Skinned enemies list their ".ani" (animation) in FILE; the mesh
            // itself is the .x with the same base name (winter_troll_000.ani
            // -> winter_troll_000.x). AssetManager lookups are case-insensitive,
            // so "gfx\\Snow_Corner.X" style names resolve too.
            if ([[file lowercaseString] hasSuffix:@".ani"]) {
                file = [[file substringToIndex:file.length - 4] stringByAppendingString:@".x"];
            }
            obj.meshFile = file.length > 0 ? file : nil;
            obj.elementType = info[1];
        }
        
        [objects addObject:obj];
        p += recordSize;
    }
    
    return objects;
}

@end
