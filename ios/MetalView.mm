#import "MetalView.h"
#import "GameEngine.h"
#import "FontRenderer.h"
#import "Camera.h"
#import "LevelRenderer.h"
#import <Metal/Metal.h>
#import <simd/simd.h>

// Direct3D-style back-face culling (clockwise = front). Verified on the real
// Santa mesh: with a left-handed camera, keeping only clockwise triangles
// reproduces the full render pixel-for-pixel. If a model ever disappears,
// set this to NO to rule culling out.
static const BOOL kCullBackFaces = YES;

// Left-handed rotation about Y (D3DXMatrixRotationY, written for column vectors).
static simd_float4x4 RotationY(float a) {
    float c = cosf(a), s = sinf(a);
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[0] = simd_make_float4( c, 0, -s, 0);
    m.columns[2] = simd_make_float4( s, 0,  c, 0);
    return m;
}

@implementation MetalView {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _meshPipelineState;
    id<MTLRenderPipelineState> _spritePipelineState;
    id<MTLTexture> _texture;
    id<MTLSamplerState> _sampler;
    id<MTLDepthStencilState> _depthState;
    id<MTLDepthStencilState> _spriteDepthState;
    id<MTLTexture> _depthTexture;
    Camera *_camera;
    LevelRenderer *_levelRenderer;
    id<MTLBuffer> _vertexBuffer;
    id<MTLBuffer> _indexBuffer;
    id<MTLBuffer> _textVertexBuffer;
    int _indexCount;
    int _textVertexCount;
    int _frameCount;
    float _angle;
    CGSize _lastDrawableSize;

    FontRenderer *_fontRenderer;
    NSString *_displayText;
}

- (instancetype)initWithFrame:(CGRect)frame {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:frame device:dev];
    if (self) {
        _device = dev;
        _camera = [[Camera alloc] init];
        self.clearColor = MTLClearColorMake(0.05, 0.05, 0.15, 1.0);
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
        self.preferredFramesPerSecond = 60;
        self.delegate = self;
        self.paused = NO;
        self.enableSetNeedsDisplay = NO;

        _frameCount = 0;
        _angle = 0;
        _indexCount = 0;
        _textVertexCount = 0;
        _lastDrawableSize = CGSizeZero;
        _textureDebugInfo = @"(loading)";
        _displayText = nil;
        _commandQueue = [_device newCommandQueue];

        MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
        sd.minFilter = MTLSamplerMinMagFilterLinear;
        sd.magFilter = MTLSamplerMinMagFilterLinear;
        sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
        _sampler = [_device newSamplerStateWithDescriptor:sd];

        MTLDepthStencilDescriptor *dd = [[MTLDepthStencilDescriptor alloc] init];
        dd.depthCompareFunction = MTLCompareFunctionLess;
        dd.depthWriteEnabled = YES;
        _depthState = [_device newDepthStencilStateWithDescriptor:dd];

        // 2D text/UI: always draw on top, never write depth.
        MTLDepthStencilDescriptor *sdd = [[MTLDepthStencilDescriptor alloc] init];
        sdd.depthCompareFunction = MTLCompareFunctionAlways;
        sdd.depthWriteEnabled = NO;
        _spriteDepthState = [_device newDepthStencilStateWithDescriptor:sdd];

        id<MTLLibrary> lib = [_device newDefaultLibrary];

        // 3D mesh pipeline
        MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
        pd.vertexFunction = [lib newFunctionWithName:@"mesh_vertex"];
        pd.fragmentFunction = [lib newFunctionWithName:@"mesh_fragment"];
        pd.colorAttachments[0].pixelFormat = self.colorPixelFormat;
        pd.depthAttachmentPixelFormat = self.depthStencilPixelFormat;

        NSError *err = nil;
        if (!pd.vertexFunction || !pd.fragmentFunction) NSLog(@"[Metal] mesh_vertex/mesh_fragment missing from Shaders.metal");
        _meshPipelineState = (pd.vertexFunction && pd.fragmentFunction)
            ? [_device newRenderPipelineStateWithDescriptor:pd error:&err] : nil;
        if (!_meshPipelineState) NSLog(@"[Metal] mesh pipeline FAILED: %@", err);

        // 2D sprite pipeline (with alpha blending)
        MTLRenderPipelineDescriptor *pd2 = [[MTLRenderPipelineDescriptor alloc] init];
        id<MTLFunction> spriteVF = [lib newFunctionWithName:@"sprite_vertex"];
        id<MTLFunction> spriteFF = [lib newFunctionWithName:@"sprite_fragment"];
        if (!spriteVF || !spriteFF) NSLog(@"[Metal] sprite_vertex/sprite_fragment missing from Shaders.metal");
        pd2.vertexFunction = spriteVF;
        pd2.fragmentFunction = spriteFF;
        pd2.colorAttachments[0].pixelFormat = self.colorPixelFormat;
        pd2.depthAttachmentPixelFormat = self.depthStencilPixelFormat;

        pd2.colorAttachments[0].blendingEnabled = YES;
        pd2.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pd2.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pd2.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pd2.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pd2.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pd2.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        if (spriteVF && spriteFF) {
            _spritePipelineState = [_device newRenderPipelineStateWithDescriptor:pd2 error:&err];
        }
        if (!_spritePipelineState) NSLog(@"[Metal] sprite pipeline FAILED: %@", err);

        _fontRenderer = [[FontRenderer alloc] initWithDevice:_device];

        // Whole-level renderer + touch camera
        _levelRenderer = [[LevelRenderer alloc] initWithDevice:_device
                                                   colorFormat:self.colorPixelFormat
                                                   depthFormat:self.depthStencilPixelFormat];
        self.multipleTouchEnabled = YES;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.maximumNumberOfTouches = 1;
        UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
        UIRotationGestureRecognizer *twist = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotate:)];
        pinch.delegate = self;
        twist.delegate = self;
        UIPanGestureRecognizer *tilt = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleTilt:)];
        tilt.minimumNumberOfTouches = 2;
        tilt.maximumNumberOfTouches = 2;
        tilt.delegate = self;
        [self addGestureRecognizer:tilt];
        [self addGestureRecognizer:pan];
        [self addGestureRecognizer:pinch];
        [self addGestureRecognizer:twist];
    }
    return self;
}

// ---------- level view ----------
- (BOOL)loadLevel:(NSString *)levelPath {
    return [_levelRenderer loadLevel:levelPath];
}

- (NSString *)levelSummary {
    return _levelRenderer.summary;
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    if (!_showLevel) return;
    CGPoint t = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];
    [_levelRenderer panByPixels:t viewHeight:self.bounds.size.height];
}

// two fingers dragging up/down = camera pitch
- (void)handleTilt:(UIPanGestureRecognizer *)g {
    if (!_showLevel) return;
    CGPoint t = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];
    CGFloat h = self.bounds.size.height;
    if (h < 1) return;
    [_levelRenderer tiltByRadians:(t.y / h) * 1.6];
}

- (void)handlePinch:(UIPinchGestureRecognizer *)g {
    if (!_showLevel) return;
    [_levelRenderer zoomByScale:g.scale];
    g.scale = 1.0;
}

- (void)handleRotate:(UIRotationGestureRecognizer *)g {
    if (!_showLevel) return;
    [_levelRenderer rotateByRadians:g.rotation];
    g.rotation = 0.0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return YES;   // pinch and twist together
}

- (BOOL)loadFont:(NSString *)fontPath {
    return [_fontRenderer loadFontFromXPK:fontPath];
}

- (void)setTextToDisplay:(NSString *)text {
    _displayText = text;
    [self rebuildTextBuffer];
}

- (void)rebuildTextBuffer {
    if (!_displayText || !_fontRenderer) return;

    CGSize ds = self.drawableSize;
    if (ds.width <= 0) ds = self.bounds.size;

    // 'scale' for FontRenderer = height of one text line in screen pixels.
    float fontScale = fminf(ds.width, ds.height) * 0.08f;

    float textWidth = [_fontRenderer textWidth:_displayText scale:fontScale];
    float penX = (ds.width - textWidth) / 2.0f;
    float penY = ds.height * 0.80f;   // lower part of the screen, clear of the debug log overlay

    NSData *verts = [_fontRenderer buildTextVertices:_displayText
                                              atPenX:penX
                                                penY:penY
                                             screenW:ds.width
                                             screenH:ds.height
                                               scale:fontScale];

    if (verts.length == 0) { _textVertexCount = 0; return; }

    _textVertexBuffer = [_device newBufferWithBytes:verts.bytes
                                              length:verts.length
                                             options:MTLResourceStorageModeShared];
    _textVertexCount = (int)(verts.length / (4 * sizeof(float)));
}

- (id<MTLTexture>)whiteTexture {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                 width:1
                                                                                height:1
                                                                             mipmapped:NO];
    d.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> t = [_device newTextureWithDescriptor:d];
    uint8_t w[4] = {255, 255, 255, 255};
    [t replaceRegion:MTLRegionMake2D(0, 0, 1, 1)
         mipmapLevel:0
           withBytes:w
         bytesPerRow:4];
    return t;
}

- (void)setMeshToRender:(MeshData *)mesh {
    if (!mesh || mesh.vertexCount <= 0 || mesh.faceCount <= 0) return;

    const float *verts = (const float *)mesh.vertices.bytes;
    const float *colors = mesh.colors ? (const float *)mesh.colors.bytes : NULL;
    const float *uvs = mesh.uvs ? (const float *)mesh.uvs.bytes : NULL;
    const uint32_t *faces = (const uint32_t *)mesh.indices.bytes;

    float minX = 1e9, maxX = -1e9;
    float minY = 1e9, maxY = -1e9;
    float minZ = 1e9, maxZ = -1e9;

    for (int i = 0; i < mesh.vertexCount; i++) {
        float x = verts[i * 3];
        float y = verts[i * 3 + 1];
        float z = verts[i * 3 + 2];
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
        if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
    }

    float cx = (minX + maxX) / 2;
    float cy = (minY + maxY) / 2;
    float cz = (minZ + maxZ) / 2;
    float maxDim = fmaxf(maxX - minX, fmaxf(maxY - minY, maxZ - minZ));
    if (maxDim < 0.001f) return;
    float s = 1.4f / maxDim;

    float *vb = new float[mesh.vertexCount * 8];
    for (int i = 0; i < mesh.vertexCount; i++) {
        vb[i * 8 + 0] = (verts[i * 3 + 0] - cx) * s;
        vb[i * 8 + 1] = (verts[i * 3 + 1] - cy) * s;
        vb[i * 8 + 2] = (verts[i * 3 + 2] - cz) * s;
        if (uvs) {
            // D3D (.x) and Metal both have V=0 at the TOP: use UVs as-is.
            // (The previous "1 - v" scrambled the texture — verified by
            // rendering Santa both ways.)
            vb[i * 8 + 3] = uvs[i * 2 + 0];
            vb[i * 8 + 4] = uvs[i * 2 + 1];
        } else {
            vb[i * 8 + 3] = 0.5f;
            vb[i * 8 + 4] = 0.5f;
        }
        if (colors) {
            vb[i * 8 + 5] = colors[i * 3 + 0];
            vb[i * 8 + 6] = colors[i * 3 + 1];
            vb[i * 8 + 7] = colors[i * 3 + 2];
        } else {
            vb[i * 8 + 5] = 1.0f;
            vb[i * 8 + 6] = 1.0f;
            vb[i * 8 + 7] = 1.0f;
        }
    }

    _vertexBuffer = [_device newBufferWithBytes:vb
                                         length:mesh.vertexCount * 8 * sizeof(float)
                                        options:MTLResourceStorageModeShared];
    delete[] vb;

    _indexBuffer = [_device newBufferWithBytes:faces
                                        length:mesh.faceCount * 3 * sizeof(uint32_t)
                                       options:MTLResourceStorageModeShared];
    _indexCount = mesh.faceCount * 3;

    id<MTLTexture> loaded = [self loadTextureForMesh:mesh];
    _texture = loaded ?: [self whiteTexture];

    if (loaded) {
        self.textureDebugInfo = [NSString stringWithFormat:@"Texture OK: %@", mesh.textureName];
    } else {
        self.textureDebugInfo = [NSString stringWithFormat:@"Texture FAILED: %@", mesh.textureName ?: @"(nil)"];
    }
}

- (id<MTLTexture>)loadTextureForMesh:(MeshData *)mesh {
    if (!mesh.textureName) return nil;

    int w = 0, h = 0;
    NSData *rgba = [GameEngine loadTextureRGBA8Named:mesh.textureName width:&w height:&h];
    if (!rgba || w <= 0 || h <= 0) return nil;

    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                 width:w
                                                                                height:h
                                                                             mipmapped:NO];
    d.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> t = [_device newTextureWithDescriptor:d];
    [t replaceRegion:MTLRegionMake2D(0, 0, w, h)
         mipmapLevel:0
           withBytes:rgba.bytes
         bytesPerRow:(NSUInteger)(w * 4)];
    return t;
}

- (void)mtkView:(MTKView *)v drawableSizeWillChange:(CGSize)s {
    [self rebuildTextBuffer];
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_meshPipelineState) return;
    BOOL levelMode = _showLevel && _levelRenderer.hasLevel;
    // PC game: pure black behind the sky cylinder; the single-mesh viewer keeps the dark blue.
    self.clearColor = levelMode ? MTLClearColorMake(0.0, 0.0, 0.0, 1.0) : MTLClearColorMake(0.05, 0.05, 0.15, 1.0);
    if (!levelMode && _indexCount <= 0 && _textVertexCount <= 0) return;

    CGSize ds = view.drawableSize;
    if (ds.width <= 0 || ds.height <= 0) return;

    if (!_depthTexture || !CGSizeEqualToSize(_lastDrawableSize, ds)) {
        MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                     width:ds.width
                                                                                    height:ds.height
                                                                                 mipmapped:NO];
        d.usage = MTLTextureUsageRenderTarget;
        d.storageMode = MTLStorageModePrivate;
        _depthTexture = [_device newTextureWithDescriptor:d];
        _lastDrawableSize = ds;
        [self rebuildTextBuffer];
    }

    _frameCount++;
    _angle += 0.01f;

    // Model is normalised to ~1.4 units; pull the camera back until it fits
    // both horizontally and vertically (landscape or portrait).
    [_camera setViewportSize:ds];
    float halfExtent = 0.8f;
    float tanHalf = tanf(_camera.fov * 0.5f);
    float aspect = (float)(ds.width / ds.height);
    float dist = fmaxf(halfExtent / tanHalf, halfExtent / (tanHalf * fminf(aspect, 1.0f))) + halfExtent;
    _camera.position = simd_make_float3(0, 0, -dist);
    simd_float4x4 mvp = simd_mul([_camera viewProjectionMatrix], RotationY(_angle));

    MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
    if (!rpd) return;
    rpd.depthAttachment.texture = _depthTexture;
    rpd.depthAttachment.clearDepth = 1.0;
    rpd.depthAttachment.loadAction = MTLLoadActionClear;
    rpd.depthAttachment.storeAction = MTLStoreActionDontCare;

    id<MTLCommandBuffer> cb = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rpd];

    // Pass 1: 3D mesh
    if (levelMode) {
        [_levelRenderer encodeInto:e depthState:_depthState viewportSize:ds];
    } else if (_vertexBuffer && _indexBuffer && _indexCount > 0) {
        [e setRenderPipelineState:_meshPipelineState];
        [e setDepthStencilState:_depthState];
        [e setFrontFacingWinding:MTLWindingClockwise];          // D3D default
        [e setCullMode:kCullBackFaces ? MTLCullModeBack : MTLCullModeNone];
        [e setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
        [e setVertexBytes:&mvp length:sizeof(mvp) atIndex:1];
        [e setFragmentTexture:_texture atIndex:0];
        [e setFragmentSamplerState:_sampler atIndex:0];
        [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                      indexCount:_indexCount
                       indexType:MTLIndexTypeUInt32
                     indexBuffer:_indexBuffer
               indexBufferOffset:0];
    }

    // Pass 2: 2D text
    if (_spritePipelineState && _textVertexBuffer && _textVertexCount > 0 && _fontRenderer.atlasTexture) {
        [e setRenderPipelineState:_spritePipelineState];
        [e setDepthStencilState:_spriteDepthState];
        [e setCullMode:MTLCullModeNone];
        [e setVertexBuffer:_textVertexBuffer offset:0 atIndex:0];
        [e setFragmentTexture:_fontRenderer.atlasTexture atIndex:0];
        [e setFragmentSamplerState:_fontRenderer.sampler atIndex:0];
        [e drawPrimitives:MTLPrimitiveTypeTriangle      // 6 vertices per glyph
              vertexStart:0
              vertexCount:_textVertexCount];
    }

    [e endEncoding];
    [cb presentDrawable:view.currentDrawable];
    [cb commit];
}

@end
