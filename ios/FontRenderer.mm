#import "FontRenderer.h"
#include "AssetManager.h"
#include "TextureLoader.h"
#include <string>
#include <vector>
#include <sstream>
#include <unordered_map>
#include <cstring>

@implementation FontChar
@end

@interface FontRenderer ()
@property (readwrite) id<MTLTexture> atlasTexture;
@property (readwrite) id<MTLSamplerState> sampler;
@property (readwrite) int atlasW;
@property (readwrite) int atlasH;
@end

@implementation FontRenderer {
    id<MTLDevice> _device;
    std::unordered_map<int, FontChar *> _chars;
    float _cellPx;   // height of one glyph cell in ATLAS pixels (52 for big_font, = em size)
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _cellPx = 0.0f;
        self.atlasTexture = nil;
        self.sampler = nil;
        self.atlasW = 0;
        self.atlasH = 0;
    }
    return self;
}

- (BOOL)loadFontFromXPK:(NSString *)fontPath {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) {
        NSLog(@"[Font] xmas.xpk not found");
        return NO;
    }
    
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) {
        NSLog(@"[Font] XPK load failed");
        return NO;
    }
    
    // ---- 1. Load font definition file ----
    std::vector<uint8_t> fontBytes = am.getAssetData([fontPath UTF8String]);
    if (fontBytes.empty()) {
        NSLog(@"[Font] Font file not found: %@", fontPath);
        return NO;
    }
    
    std::string fontText((const char *)fontBytes.data(), fontBytes.size());
    std::istringstream stream(fontText);
    std::string line;
    
    while (std::getline(stream, line)) {
        if (line.empty()) continue;
        
        std::istringstream iss(line);
        std::string token;
        iss >> token;
        
        if (token == "Char") {
            int page = 0, code = 0;
            float u0 = 0, v0 = 0, u1 = 0, v1 = 0;
            float offX = 0, adv = 0, offY = 0;
            
            iss >> page >> code >> u0 >> v0 >> u1 >> v1 >> offX >> adv >> offY;
            
            if (page == 0 && code > 0) {
                FontChar *fc = [[FontChar alloc] init];
                fc.code = code;
                fc.u0 = u0;
                fc.v0 = v0;
                fc.u1 = u1;
                fc.v1 = v1;
                fc.offsetX = offX;
                fc.advance = adv;
                fc.offsetY = offY;
                _chars[code] = fc;
            }
        }
    }
    
    NSLog(@"[Font] Parsed %lu characters", (unsigned long)_chars.size());
    if (_chars.empty()) {
        NSLog(@"[Font] No characters parsed");
        return NO;
    }
    
    // ---- 2. Load texture atlas ----
    std::vector<uint8_t> texBytes = am.getAssetData("maps\\big_font00.dds");
    if (texBytes.empty()) {
        NSLog(@"[Font] Texture atlas not found: maps\\big_font00.dds");
        return NO;
    }
    
    std::vector<uint8_t> rgba;
    int w = 0, h = 0;
    if (!TextureLoader::decodeDDS(texBytes, rgba, w, h)) {
        NSLog(@"[Font] Texture decode failed");
        return NO;
    }
    
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                  width:w
                                                                                 height:h
                                                                              mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    self.atlasTexture = [_device newTextureWithDescriptor:td];
    [self.atlasTexture replaceRegion:MTLRegionMake2D(0, 0, w, h)
                         mipmapLevel:0
                           withBytes:rgba.data()
                         bytesPerRow:(NSUInteger)(w * 4)];
    
    MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
    sd.minFilter = MTLSamplerMinMagFilterLinear;
    sd.magFilter = MTLSamplerMinMagFilterLinear;
    sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
    self.sampler = [_device newSamplerStateWithDescriptor:sd];
    
    self.atlasW = w;
    self.atlasH = h;

    // Glyph metrics in the .txt are in units of the glyph-cell height
    // ("em"): e.g. '!' has advance 0.3077 == 16px / 52px. Using anything
    // else (the old code mixed a hard-coded 24px em with atlas-pixel quad
    // sizes) makes neighbouring glyphs overlap.
    FontChar *ref = _chars.count('A') ? _chars['A'] : nil;
    if (!ref) ref = _chars.begin()->second;
    _cellPx = (ref.v1 - ref.v0) * (float)h;
    if (_cellPx < 1.0f) _cellPx = 52.0f;
    
    NSLog(@"[Font] ✅ Loaded: %lu chars, texture %dx%d", (unsigned long)_chars.size(), w, h);
    return YES;
}

- (float)textWidth:(NSString *)text scale:(float)fontPx {
    // 'fontPx' = height in SCREEN pixels of one text line (em size).
    float width = 0;
    const char *cstr = [text UTF8String];
    size_t n = strlen(cstr);
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)cstr[i];
        auto it = _chars.find(c);
        if (it != _chars.end()) {
            width += it->second.advance * fontPx;
        } else {
            width += fontPx * 0.3f;   // unknown glyph / space
        }
    }
    return width;
}

// Returns 6 vertices per glyph (two triangles, TRIANGLE LIST), each vertex
// = (ndcX, ndcY, u, v). The old code emitted 4 vertices per glyph but drew
// ALL glyphs as ONE triangle strip, which stitches the end of each letter to
// the start of the next with garbage triangles.
- (NSData *)buildTextVertices:(NSString *)text
                      atPenX:(float)penX
                        penY:(float)penY
                     screenW:(float)screenW
                     screenH:(float)screenH
                       scale:(float)fontPx {
    std::vector<float> verts;
    if (_cellPx <= 0.0f || self.atlasW <= 0 || self.atlasH <= 0) return [NSData data];

    float k = fontPx / _cellPx;               // screen px per atlas px
    float penXCur = penX;
    float penYCur = penY;

    const char *cstr = [text UTF8String];
    size_t n = strlen(cstr);
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)cstr[i];

        if (c == '\n') {
            penXCur = penX;
            penYCur += fontPx * 1.2f;
            continue;
        }

        auto it = _chars.find(c);
        if (it == _chars.end()) {
            penXCur += fontPx * 0.3f;          // space etc.
            continue;
        }
        FontChar *fc = it->second;

        float charW = (fc.u1 - fc.u0) * (float)self.atlasW * k;
        float charH = (fc.v1 - fc.v0) * (float)self.atlasH * k;
        float cx = penXCur + fc.offsetX * fontPx;
        float cy = penYCur + fc.offsetY * fontPx;

        // screen px (top-left origin) -> NDC (y up)
        float xl = (cx / screenW) * 2.0f - 1.0f;
        float xr = ((cx + charW) / screenW) * 2.0f - 1.0f;
        float yt = 1.0f - (cy / screenH) * 2.0f;
        float yb = 1.0f - ((cy + charH) / screenH) * 2.0f;

        // Atlas V=0 is the TOP row (same in D3D and Metal), so the glyph's
        // v0 belongs to the top edge of the quad. (The old "V-FLIP FIX"
        // swapped v0/v1, which renders every letter upside-down.)
        float u0 = fc.u0, u1 = fc.u1;
        float v0 = fc.v0, v1 = fc.v1;

        // Triangle 1: TL, TR, BL
        verts.insert(verts.end(), { xl, yt, u0, v0,   xr, yt, u1, v0,   xl, yb, u0, v1 });
        // Triangle 2: TR, BR, BL
        verts.insert(verts.end(), { xr, yt, u1, v0,   xr, yb, u1, v1,   xl, yb, u0, v1 });

        penXCur += fc.advance * fontPx;
    }

    return [NSData dataWithBytes:verts.data() length:verts.size() * sizeof(float)];
}

@end
