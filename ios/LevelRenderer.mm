#import "LevelRenderer.h"
#import "GameEngine.h"
#import "Camera.h"
#import <simd/simd.h>
#include "ElementCatalog.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cstring>

static const float kPi = 3.14159265358979f;

// Column-major model matrix = Translate * RotateY(angle) * UniformScale.
// RotateY is the left-handed D3DXMatrixRotationY (for column vectors):
//   x' =  c*x + s*z,   z' = -s*x + c*z
static simd_float4x4 LevelModelMatrix(float x, float y, float z, float angle, float scale) {
    float c = cosf(angle) * scale;
    float s = sinf(angle) * scale;
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[0] = simd_make_float4( c,     0, -s,    0);
    m.columns[1] = simd_make_float4( 0, scale,  0,    0);
    m.columns[2] = simd_make_float4( s,     0,  c,    0);
    m.columns[3] = simd_make_float4( x,     y,  z,    1);
    return m;
}

// ---------- small helper classes ----------
@interface LevelGPUMesh : NSObject
@property (strong, nonatomic) id<MTLBuffer> vertexBuffer;   // 8 floats / vertex: pos3 uv2 color3
@property (strong, nonatomic) id<MTLBuffer> indexBuffer;    // uint32
@property (nonatomic) NSUInteger indexCount;
@property (nonatomic) float minY;                            // lowest model-space y (feet / base)
@property (strong, nonatomic) id<MTLTexture> texture;
@end
@implementation LevelGPUMesh
@end

@interface LevelBatch : NSObject
@property (strong, nonatomic) LevelGPUMesh *mesh;
@property (strong, nonatomic) NSMutableData *models;        // packed simd_float4x4
@property (nonatomic) NSUInteger count;
@end
@implementation LevelBatch
@end

// ---------- renderer ----------
@implementation LevelRenderer {
    id<MTLDevice> _device;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLSamplerState> _sampler;
    id<MTLRenderPipelineState> _skyPipeline;
    id<MTLDepthStencilState> _skyDepth;
    LevelGPUMesh *_skyMesh;   // gfx\himmel.x: open cylinder (r=65.7, h=26) with the night-sky texture
    id<MTLTexture> _whiteTexture;
    Camera *_camera;
    NSMutableArray<LevelBatch *> *_batches;
    NSMutableDictionary<NSString *, id<MTLTexture>> *_textureCache;

    simd_float3 _target;
    simd_float3 _boundsMin;
    simd_float3 _boundsMax;
    float _dist;
    float _yaw;
    float _pitch;
    NSUInteger _texMissing;   // unique textures that fell back to white

    NSArray<LevelObject *> *_objects;
    simd_float3 _spawnPoint;
    LevelBatch *_santaBatch;
    float _santaScale;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                   colorFormat:(MTLPixelFormat)colorFormat
                   depthFormat:(MTLPixelFormat)depthFormat {
    self = [super init];
    if (!self) return nil;

    _device = device;
    _batches = [NSMutableArray array];
    _textureCache = [NSMutableDictionary dictionary];
    _summary = @"(no level loaded)";
    _hasLevel = NO;
    _objectCount = 0;

    _camera = [[Camera alloc] init];
    _camera.up = simd_make_float3(0, 1, 0);
    _camera.nearPlane = 0.5f;
    _camera.farPlane = 3000.0f;

    _target = simd_make_float3(0, 0, 0);
    _boundsMin = simd_make_float3(-50, -50, -50);
    _boundsMax = simd_make_float3(50, 50, 50);
    _dist = 32.0f;
    _yaw = 0.0f;
    _pitch = 0.95f;   // ~54 degrees looking down

    // Level shaders live in Shaders.metal: level_vertex / level_fragment
    id<MTLLibrary> lib = [device newDefaultLibrary];
    id<MTLFunction> vf = [lib newFunctionWithName:@"level_vertex"];
    id<MTLFunction> ff = [lib newFunctionWithName:@"level_fragment"];
    if (vf && ff) {
        MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
        pd.vertexFunction = vf;
        pd.fragmentFunction = ff;
        pd.colorAttachments[0].pixelFormat = colorFormat;
        pd.depthAttachmentPixelFormat = depthFormat;
        NSError *err = nil;
        _pipeline = [device newRenderPipelineStateWithDescriptor:pd error:&err];
        if (!_pipeline) NSLog(@"[Level] pipeline FAILED: %@", err);
    } else {
        NSLog(@"[Level] level_vertex/level_fragment missing from Shaders.metal");
    }

    // Sky: the game's own sky cylinder (gfx\himmel.x) drawn unlit around the camera.
    // Vertex layout is identical to the level meshes, so the old mesh_vertex /
    // mesh_fragment pair (uniform = one MVP matrix at buffer 1) does the job.
    id<MTLFunction> skyVF = [lib newFunctionWithName:@"mesh_vertex"];
    id<MTLFunction> skyFF = [lib newFunctionWithName:@"mesh_fragment"];
    if (skyVF && skyFF) {
        MTLRenderPipelineDescriptor *sp = [[MTLRenderPipelineDescriptor alloc] init];
        sp.vertexFunction = skyVF;
        sp.fragmentFunction = skyFF;
        sp.colorAttachments[0].pixelFormat = colorFormat;
        sp.depthAttachmentPixelFormat = depthFormat;
        NSError *skyErr = nil;
        _skyPipeline = [device newRenderPipelineStateWithDescriptor:sp error:&skyErr];
        if (!_skyPipeline) NSLog(@"[Level] sky pipeline FAILED: %@", skyErr);
    }
    MTLDepthStencilDescriptor *skyDD = [[MTLDepthStencilDescriptor alloc] init];
    skyDD.depthCompareFunction = MTLCompareFunctionAlways;
    skyDD.depthWriteEnabled = NO;
    _skyDepth = [device newDepthStencilStateWithDescriptor:skyDD];

    MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
    sd.minFilter = MTLSamplerMinMagFilterLinear;
    sd.magFilter = MTLSamplerMinMagFilterLinear;
    sd.mipFilter = MTLSamplerMipFilterLinear;
    sd.sAddressMode = MTLSamplerAddressModeRepeat;   // platform / snow textures tile
    sd.tAddressMode = MTLSamplerAddressModeRepeat;
    sd.maxAnisotropy = 4;
    _sampler = [device newSamplerStateWithDescriptor:sd];

    uint8_t white[4] = {255, 255, 255, 255};
    _whiteTexture = [self makeTextureRGBA:white width:1 height:1];
    return self;
}

// RGBA8 texture with a full CPU-generated mip chain (box filter).
- (id<MTLTexture>)makeTextureRGBA:(const uint8_t *)rgba width:(int)w height:(int)h {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                 width:(NSUInteger)w
                                                                                height:(NSUInteger)h
                                                                             mipmapped:YES];
    d.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> t = [_device newTextureWithDescriptor:d];
    if (!t) return nil;

    std::vector<uint8_t> cur(rgba, rgba + (size_t)w * h * 4);
    int cw = w, ch = h;
    for (NSUInteger level = 0; level < t.mipmapLevelCount; level++) {
        [t replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)cw, (NSUInteger)ch)
             mipmapLevel:level
               withBytes:cur.data()
             bytesPerRow:(NSUInteger)cw * 4];
        if (cw == 1 && ch == 1) break;

        int nw = std::max(cw / 2, 1);
        int nh = std::max(ch / 2, 1);
        std::vector<uint8_t> next((size_t)nw * nh * 4);
        for (int y = 0; y < nh; y++) {
            int y0 = std::min(2 * y, ch - 1);
            int y1 = std::min(2 * y + 1, ch - 1);
            for (int x = 0; x < nw; x++) {
                int x0 = std::min(2 * x, cw - 1);
                int x1 = std::min(2 * x + 1, cw - 1);
                for (int c = 0; c < 4; c++) {
                    int sum = cur[((size_t)y0 * cw + x0) * 4 + c] + cur[((size_t)y0 * cw + x1) * 4 + c]
                            + cur[((size_t)y1 * cw + x0) * 4 + c] + cur[((size_t)y1 * cw + x1) * 4 + c];
                    next[((size_t)y * nw + x) * 4 + c] = (uint8_t)((sum + 2) / 4);
                }
            }
        }
        cur.swap(next);
        cw = nw;
        ch = nh;
    }
    return t;
}

- (id<MTLTexture>)textureNamed:(NSString *)xpkPath {
    if (!xpkPath) { _texMissing++; return _whiteTexture; }
    NSString *key = [xpkPath lowercaseString];
    id<MTLTexture> cached = _textureCache[key];
    if (cached) return cached;

    int w = 0, h = 0;
    NSData *rgba = [GameEngine loadTextureRGBA8Named:xpkPath width:&w height:&h];
    id<MTLTexture> t = nil;
    if (rgba && w > 0 && h > 0 && rgba.length >= (NSUInteger)w * h * 4) {
        t = [self makeTextureRGBA:(const uint8_t *)rgba.bytes width:w height:h];
    }
    if (!t) {
        NSLog(@"[Level] texture missing: %@ (using white)", xpkPath);
        _texMissing++;
        t = _whiteTexture;
    }
    _textureCache[key] = t;
    return t;
}

- (LevelGPUMesh *)buildGPUMeshForFile:(NSString *)file {
    MeshData *md = [GameEngine extractMeshFromAsset:file];
    if (!md || md.vertexCount <= 0 || md.faceCount <= 0) return nil;

    NSUInteger vc = (NSUInteger)md.vertexCount;
    if (md.vertices.length < vc * 3 * sizeof(float)) return nil;
    if (md.indices.length < (NSUInteger)md.faceCount * 3 * sizeof(uint32_t)) return nil;

    const float *verts = (const float *)md.vertices.bytes;
    const float *uvs = (md.uvs.length >= vc * 2 * sizeof(float)) ? (const float *)md.uvs.bytes : NULL;

    std::vector<float> vb(vc * 8);
    float minY = 1e9f;
    for (NSUInteger i = 0; i < vc; i++) {
        minY = fminf(minY, verts[i * 3 + 1]);
        vb[i * 8 + 0] = verts[i * 3 + 0];   // raw model space: scale + rotation come from the instance matrix
        vb[i * 8 + 1] = verts[i * 3 + 1];
        vb[i * 8 + 2] = verts[i * 3 + 2];
        vb[i * 8 + 3] = uvs ? uvs[i * 2 + 0] : 0.5f;   // V used as-is (D3D and Metal: V=0 at top)
        vb[i * 8 + 4] = uvs ? uvs[i * 2 + 1] : 0.5f;
        vb[i * 8 + 5] = 1.0f;
        vb[i * 8 + 6] = 1.0f;
        vb[i * 8 + 7] = 1.0f;
    }

    LevelGPUMesh *gm = [[LevelGPUMesh alloc] init];
    gm.vertexBuffer = [_device newBufferWithBytes:vb.data()
                                           length:vb.size() * sizeof(float)
                                          options:MTLResourceStorageModeShared];
    gm.indexBuffer = [_device newBufferWithBytes:md.indices.bytes
                                          length:(NSUInteger)md.faceCount * 3 * sizeof(uint32_t)
                                         options:MTLResourceStorageModeShared];
    gm.indexCount = (NSUInteger)md.faceCount * 3;
    gm.minY = minY;
    gm.texture = [self textureNamed:md.textureName];
    if (!gm.vertexBuffer || !gm.indexBuffer) return nil;
    return gm;
}

- (BOOL)loadLevel:(NSString *)levelPath {
    _hasLevel = NO;
    _objectCount = 0;
    _texMissing = 0;
    [_batches removeAllObjects];

    // element catalog (model file, SCALING, TYPE) — parsed once
    ElementCatalog &catalog = ElementCatalog::shared();
    if (catalog.size() == 0) {
        NSData *ct = [GameEngine loadAssetNamed:@"data\\elements.txt"];
        if (ct) catalog.parse(std::string((const char *)ct.bytes, (size_t)ct.length));
    }
    if (catalog.size() == 0) {
        _summary = @"element catalog missing";
        return NO;
    }

    NSArray<LevelObject *> *objects = [GameEngine parseLevelData:levelPath];
    if (objects.count == 0) {
        _summary = [NSString stringWithFormat:@"%@: no objects", levelPath];
        return NO;
    }
    _objects = objects;

    NSMutableDictionary<NSString *, LevelBatch *> *byMesh = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *failedMeshes = [NSMutableSet set];
    NSUInteger placed = 0, skipped = 0;
    BOOL haveStart = NO;
    simd_float3 bmin = simd_make_float3(1e9f, 1e9f, 1e9f);
    simd_float3 bmax = simd_make_float3(-1e9f, -1e9f, -1e9f);

    for (LevelObject *o in objects) {
        const ElementDef *def = catalog.find(std::string([o.objectName UTF8String]));
        if (!def || def->meshFile.empty()) { skipped++; continue; }

        NSString *meshFile = [NSString stringWithUTF8String:def->meshFile.c_str()];
        NSString *key = [meshFile lowercaseString];
        if ([key containsString:@"dummy"]) { skipped++; continue; }   // invisible collision helper
        if ([failedMeshes containsObject:key]) { skipped++; continue; }

        LevelBatch *batch = byMesh[key];
        if (!batch) {
            LevelGPUMesh *gm = [self buildGPUMeshForFile:meshFile];
            if (!gm) {
                NSLog(@"[Level] mesh failed: %@", meshFile);
                [failedMeshes addObject:key];
                skipped++;
                continue;
            }
            batch = [[LevelBatch alloc] init];
            batch.mesh = gm;
            batch.models = [NSMutableData data];
            byMesh[key] = batch;
            [_batches addObject:batch];
        }

        float s = def->scaling;
        float scale = (s >= 1.0f) ? (s / 100.0f) : s;   // percent vs. direct (see header)
        if (scale <= 0.0f) scale = 0.01f;
        float angle = (float)(o.variant & 3) * (kPi * 0.5f);

        simd_float4x4 m = LevelModelMatrix(o.x, o.y, o.z, angle, scale);
        [batch.models appendBytes:&m length:sizeof(m)];
        batch.count++;
        placed++;

        if (!haveStart) { _target = simd_make_float3(o.x, o.y, o.z); haveStart = YES; }
        bmin = simd_min(bmin, simd_make_float3(o.x, o.y, o.z));
        bmax = simd_max(bmax, simd_make_float3(o.x, o.y, o.z));
    }

    if (placed == 0) {
        _summary = [NSString stringWithFormat:@"%@: nothing renderable", levelPath];
        return NO;
    }

    // Sky cylinder: himmel.x, texture maps\himmel.dds (8-bit palette, 1024x1024)
    _skyMesh = [self buildGPUMeshForFile:@"gfx\\himmel.x"];

    // Santa at the start point, standing on the first platform.
    // Model: bind pose, feet at y = 0 after the frame transform (see GameEngine.mm),
    // scale 0.014 (same modelling scale as the troll) = ~1.8 world units tall.
    BOOL santaPlaced = NO;
    _santaBatch = nil;
    if (haveStart) {
        LevelGPUMesh *sg = [self buildGPUMeshForFile:@"gfx\\weihnachtsman_000.x"];
        if (sg) {
            const float santaScale = 0.014f;
            float sy = _target.y - sg.minY * santaScale;
            LevelBatch *sb = [[LevelBatch alloc] init];
            sb.mesh = sg;
            sb.models = [NSMutableData data];
            simd_float4x4 sm = LevelModelMatrix(_target.x, sy, _target.z, 0.0f, santaScale);
            [sb.models appendBytes:&sm length:sizeof(sm)];
            sb.count = 1;
            [_batches addObject:sb];
            santaPlaced = YES;
            _santaBatch = sb;
            _santaScale = santaScale;
            _spawnPoint = simd_make_float3(_target.x, sy, _target.z);
        }
    }

    _boundsMin = bmin - simd_make_float3(15, 15, 15);
    _boundsMax = bmax + simd_make_float3(15, 15, 15);
    _objectCount = placed;
    _hasLevel = YES;
    _summary = [NSString stringWithFormat:@"%@\n%lu objects, %lu models, %lu skipped\ntextures: %lu unique, %lu missing (white)\nsky: %@   santa: %@\nx %.0f..%.0f  z %.0f..%.0f",
                levelPath, (unsigned long)placed, (unsigned long)_batches.count, (unsigned long)skipped,
                (unsigned long)_textureCache.count, (unsigned long)_texMissing,
                (_skyPipeline && _skyMesh && _skyMesh.texture != _whiteTexture) ? @"ok" : @"MISSING",
                santaPlaced ? @"placed" : @"MISSING",
                bmin.x, bmax.x, bmin.z, bmax.z];
    NSLog(@"[Level] %@", _summary);
    return YES;
}

- (void)encodeInto:(id<MTLRenderCommandEncoder>)e
        depthState:(id<MTLDepthStencilState>)depthState
      viewportSize:(CGSize)size {
    if (!_pipeline || !_hasLevel || size.height <= 0) return;

    [_camera setViewportSize:size];
    float cp = cosf(_pitch), sp = sinf(_pitch);
    simd_float3 fwd = simd_make_float3(sinf(_yaw), 0.0f, cosf(_yaw));   // horizontal look direction
    _camera.target = _target;
    _camera.position = _target - fwd * (cp * _dist) + simd_make_float3(0.0f, sp * _dist, 0.0f);
    simd_float4x4 viewProj = [_camera viewProjectionMatrix];

    // Sky cylinder centred on the camera: no depth test/write, no culling, drawn first.
    // Its UVs repeat ~8.8x around, v=0 is the top rim (stars), v~0.7 the mountain line,
    // the lower part is black (that is the "void" below the platforms in the PC game).
    if (_skyPipeline && _skyMesh) {
        simd_float4x4 skyModel = matrix_identity_float4x4;
        skyModel.columns[3] = simd_make_float4(_camera.position.x, _camera.position.y, _camera.position.z, 1.0f);
        simd_float4x4 skyMVP = simd_mul(viewProj, skyModel);
        [e setRenderPipelineState:_skyPipeline];
        [e setDepthStencilState:_skyDepth];
        [e setCullMode:MTLCullModeNone];
        [e setVertexBuffer:_skyMesh.vertexBuffer offset:0 atIndex:0];
        [e setVertexBytes:&skyMVP length:sizeof(skyMVP) atIndex:1];
        [e setFragmentTexture:_skyMesh.texture atIndex:0];
        [e setFragmentSamplerState:_sampler atIndex:0];
        [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                      indexCount:_skyMesh.indexCount
                       indexType:MTLIndexTypeUInt32
                     indexBuffer:_skyMesh.indexBuffer
               indexBufferOffset:0];
    }

    [e setRenderPipelineState:_pipeline];
    [e setDepthStencilState:depthState];
    [e setFrontFacingWinding:MTLWindingClockwise];   // D3D default
    [e setCullMode:MTLCullModeBack];
    [e setVertexBytes:&viewProj length:sizeof(viewProj) atIndex:1];
    [e setFragmentSamplerState:_sampler atIndex:0];

    for (LevelBatch *b in _batches) {
        LevelGPUMesh *m = b.mesh;
        [e setVertexBuffer:m.vertexBuffer offset:0 atIndex:0];
        [e setFragmentTexture:m.texture atIndex:0];
        const uint8_t *bytes = (const uint8_t *)b.models.bytes;
        for (NSUInteger i = 0; i < b.count; i++) {
            simd_float4x4 model;
            memcpy(&model, bytes + i * sizeof(simd_float4x4), sizeof(model));
            [e setVertexBytes:&model length:sizeof(model) atIndex:2];
            [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                          indexCount:m.indexCount
                           indexType:MTLIndexTypeUInt32
                         indexBuffer:m.indexBuffer
                   indexBufferOffset:0];
        }
    }
}

// ---------- camera control ----------
- (void)clampTarget {
    _target = simd_max(_target, _boundsMin);
    _target = simd_min(_target, _boundsMax);
}

- (void)panByPixels:(CGPoint)delta viewHeight:(CGFloat)viewHeight {
    if (viewHeight < 1) return;
    float k = 2.0f * _dist * tanf(_camera.fov * 0.5f) / (float)viewHeight;   // world units per screen point
    simd_float3 right = simd_make_float3(cosf(_yaw), 0.0f, -sinf(_yaw));
    simd_float3 fwd = simd_make_float3(sinf(_yaw), 0.0f, cosf(_yaw));
    // the ground follows the finger; vertical motion is foreshortened by the pitch
    _target = _target - right * ((float)delta.x * k) + fwd * ((float)delta.y * k / fmaxf(sinf(_pitch), 0.3f));
    [self clampTarget];
}

- (void)zoomByScale:(CGFloat)scale {
    if (scale <= 0.01) return;
    _dist = fminf(fmaxf(_dist / (float)scale, 6.0f), 400.0f);
}

- (void)tiltByRadians:(CGFloat)radians {
    _pitch = fminf(fmaxf(_pitch + (float)radians, 0.08f), 1.45f);   // 5 deg (nearly horizontal) .. 83 deg (top-down)
}

- (void)rotateByRadians:(CGFloat)radians {
    _yaw -= (float)radians;   // scene follows the fingers (clockwise on screen)
}

// ---------- live Santa (Play mode) ----------
- (void)setSantaPosition:(simd_float3)position facingAngle:(float)facingAngle {
    if (!_santaBatch) return;
    simd_float4x4 m = LevelModelMatrix(position.x, position.y, position.z, facingAngle, _santaScale);
    NSMutableData *models = _santaBatch.models;
    if (models.length != sizeof(m)) models = [NSMutableData dataWithLength:sizeof(m)];
    memcpy(models.mutableBytes, &m, sizeof(m));
    _santaBatch.models = models;
    _santaBatch.count = 1;
}

- (void)setCameraTarget:(simd_float3)target {
    _target = target;
}

@end
