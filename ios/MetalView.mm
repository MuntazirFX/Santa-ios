#import "MetalView.h"
#import "GameEngine.h"
#import "FontRenderer.h"
#import "Camera.h"
#import "LevelRenderer.h"
#import "PhysicsWorld.h"
#import "CharacterController.h"
#include "TextureLoader.h"
#import <Metal/Metal.h>
#import <simd/simd.h>
#import <QuartzCore/QuartzCore.h>

// Direct3D-style back-face culling (clockwise = front). Verified on the real
// Santa mesh: with a left-handed camera, keeping only clockwise triangles
// reproduces the full render pixel-for-pixel. If a model ever disappears,
// set this to NO to rule culling out.
static const BOOL kCullBackFaces = YES;
static const float kPi = 3.14159265358979f;

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

    // Gameplay — DINPUT8 replacement (on-screen touch controls) + real
    // level collision, wired to the actual working level parser
    // ([GameEngine parseLevelData:], same data LevelRenderer draws).
    PhysicsWorld *_physicsWorld;
    CharacterController *_character;
    BOOL _controlsEnabled;
    BOOL _showingGameplayDebugText;
    CFTimeInterval _lastFrameTime;
    UIButton *_btnLeft, *_btnRight, *_btnJump;

    // Main menu overlay (matches the original PC title screen: maps\sc.dds
    // has the "CDV FunLine" banner + "cdv" logo + the "Santa Claus in
    // Trouble" cursive title baked into one texture; maps\joymania.dds has
    // the "JD Joymania Development" corner logo. Both also contain other,
    // unrelated art lower in the same texture — cropped out below using
    // exact alpha-channel bounding boxes measured from the real files, not
    // guessed). Drawn on top of the already-working Level view; "START
    // GAME" hides this and reveals the ◀ ▶ ▲ movement controls.
    BOOL _inMainMenu;
    id<MTLTexture> _scTexture, _joymaniaTexture;
    id<MTLBuffer> _scVertexBuffer, _joymaniaVertexBuffer;
    int _scVertexCount, _joymaniaVertexCount;
    id<MTLBuffer> _menuTextVertexBuffer[4];
    int _menuTextVertexCount[4];
    UIButton *_btnStart, *_btnHighscores, *_btnOptions, *_btnQuit;
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

        // Gameplay: PhysicsWorld + CharacterController + on-screen buttons
        // (DINPUT8 replacement — the exe read arrow keys/space here).
        _physicsWorld = [[PhysicsWorld alloc] init];
        _character = [[CharacterController alloc] init];
        _character.physicsWorld = _physicsWorld;
        _controlsEnabled = NO;
        _lastFrameTime = 0;

        // Real frames are set in -layoutSubviews (not here): `frame` above is
        // often CGRectZero at this point (the owning UIViewController's view
        // isn't in a window yet), so anything positioned from it here would
        // be placed off-screen and never move — autoresizing only resizes
        // this view itself, not these subviews' already-fixed frames.
        _btnLeft = [self makeControlButton:@"◀" frame:CGRectZero];
        _btnRight = [self makeControlButton:@"▶" frame:CGRectZero];
        _btnJump = [self makeControlButton:@"▲" frame:CGRectZero];
        [_btnLeft addTarget:self action:@selector(leftDown) forControlEvents:UIControlEventTouchDown];
        [_btnLeft addTarget:self action:@selector(leftUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [_btnRight addTarget:self action:@selector(rightDown) forControlEvents:UIControlEventTouchDown];
        [_btnRight addTarget:self action:@selector(rightUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [_btnJump addTarget:self action:@selector(jumpTapped) forControlEvents:UIControlEventTouchDown];
        _btnLeft.hidden = _btnRight.hidden = _btnJump.hidden = YES; // shown once a level with a playable character loads
        [self addSubview:_btnLeft];
        [self addSubview:_btnRight];
        [self addSubview:_btnJump];

        // Main menu buttons — invisible hit targets over the bitmap-font
        // labels drawn by the Metal sprite pass (same "transparent UIButton
        // on top of custom-rendered text" pattern as the ◀▶▲ controls, so
        // taps land on the real "START GAME" glyphs instead of guessed rects).
        _inMainMenu = YES;
        _btnStart = [self makeMenuHitTarget];
        _btnHighscores = [self makeMenuHitTarget];
        _btnOptions = [self makeMenuHitTarget];
        _btnQuit = [self makeMenuHitTarget];
        [_btnStart addTarget:self action:@selector(startGameTapped) forControlEvents:UIControlEventTouchUpInside];
        [_btnHighscores addTarget:self action:@selector(highscoresTapped) forControlEvents:UIControlEventTouchUpInside];
        [_btnOptions addTarget:self action:@selector(optionsTapped) forControlEvents:UIControlEventTouchUpInside];
        [_btnQuit addTarget:self action:@selector(quitTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_btnStart];
        [self addSubview:_btnHighscores];
        [self addSubview:_btnOptions];
        [self addSubview:_btnQuit];
    }
    return self;
}

- (UIButton *)makeMenuHitTarget {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; // invisible — the Metal pass draws the real label
    b.backgroundColor = [UIColor clearColor];
    return b;
}

// Shared layout for the 4 menu items — bottom-left stack, matching the PC
// title screen's START GAME / HIGHSCORES / OPTIONS / (gap) / QUIT layout.
// Used both to position the invisible tap targets and to place the
// bitmap-font label text, so the two always line up.
- (void)computeMenuButtonRects:(CGRect[4])out {
    CGFloat rowH = fminf(self.bounds.size.height * 0.05f, 40.0f);
    CGFloat left = self.bounds.size.width * 0.04f;
    CGFloat w = self.bounds.size.width * 0.5f;
    CGFloat bottom = self.bounds.size.height * 0.86f; // QUIT's baseline, matches reference proportions
    out[3] = CGRectMake(left, bottom, w, rowH);                    // QUIT
    out[2] = CGRectMake(left, bottom - rowH * 2.3f, w, rowH);      // OPTIONS
    out[1] = CGRectMake(left, bottom - rowH * 3.5f, w, rowH);      // HIGHSCORES
    out[0] = CGRectMake(left, bottom - rowH * 4.7f, w, rowH);      // START GAME
}

- (void)layoutMenuHitTargets {
    CGRect r[4]; [self computeMenuButtonRects:r];
    _btnStart.frame = r[0];
    _btnHighscores.frame = r[1];
    _btnOptions.frame = r[2];
    _btnQuit.frame = r[3];
    BOOL show = _inMainMenu;
    _btnStart.hidden = _btnHighscores.hidden = _btnOptions.hidden = _btnQuit.hidden = !show;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Real, always-current positions — self.bounds is correct here even on
    // the very first layout pass, unlike the `frame` initWithFrame: got.
    CGFloat bs = 64, margin = 24;
    CGFloat bottom = self.bounds.size.height - bs - margin;
    _btnLeft.frame = CGRectMake(margin, bottom, bs, bs);
    _btnRight.frame = CGRectMake(margin + bs + 16, bottom, bs, bs);
    _btnJump.frame = CGRectMake(self.bounds.size.width - bs - margin, bottom, bs, bs);
    [self layoutMenuHitTargets];
    if (_scTexture || _joymaniaTexture) [self rebuildMenuSpriteBuffers]; // re-lay-out on rotation/resize
}

- (UIButton *)makeControlButton:(NSString *)title frame:(CGRect)frame {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    b.layer.cornerRadius = 32;
    b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.28];
    b.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    b.layer.borderWidth = 1.5;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:28];
    return b;
}

- (void)leftDown  { [_character setInputLeft:YES]; }
- (void)leftUp    { [_character setInputLeft:NO]; }
- (void)rightDown { [_character setInputRight:YES]; }
- (void)rightUp   { [_character setInputRight:NO]; }
- (void)jumpTapped { [_character triggerJump]; }

// ---------- main menu ----------
- (void)startGameTapped {
    _inMainMenu = NO;
    [self layoutMenuHitTargets];
    _btnLeft.hidden = _btnRight.hidden = _btnJump.hidden = !_controlsEnabled;
}
- (void)highscoresTapped {
    // No highscore storage exists yet (this port doesn't have score.dat
    // support) — visual-only for now, matches the exe's screen but does
    // nothing further.
}
- (void)optionsTapped {
    // No settings screen exists yet — visual-only for now.
}
- (void)quitTapped {
    // iOS apps don't self-terminate (Apple HIG) — nothing to do here.
}

- (id<MTLTexture>)loadXPKTexture:(NSString *)assetPath {
    NSData *raw = [GameEngine loadAssetNamed:assetPath];
    if (!raw) { NSLog(@"[Menu] asset not found: %@", assetPath); return nil; }
    std::vector<uint8_t> bytes((const uint8_t *)raw.bytes, (const uint8_t *)raw.bytes + raw.length);
    std::vector<uint8_t> rgba; int w = 0, h = 0;
    if (!TextureLoader::decodeImage(bytes, rgba, w, h)) { NSLog(@"[Menu] decode failed: %@", assetPath); return nil; }
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                    width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> tex = [_device newTextureWithDescriptor:td];
    [tex replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:rgba.data() bytesPerRow:(NSUInteger)(w * 4)];
    return tex;
}

// Builds a 6-vertex (ndcX,ndcY,u,v) textured quad for a screen-space rect
// (points) cropped to a UV sub-rect — same vertex layout _spritePipelineState
// already expects (FontRenderer's buildTextVertices uses the same format).
- (NSData *)buildSpriteQuadInRect:(CGRect)rectPoints uv:(CGRect)uvRect screenSize:(CGSize)screenSize {
    float x0 = (float)(rectPoints.origin.x / screenSize.width) * 2.0f - 1.0f;
    float x1 = (float)((rectPoints.origin.x + rectPoints.size.width) / screenSize.width) * 2.0f - 1.0f;
    float y0 = 1.0f - (float)(rectPoints.origin.y / screenSize.height) * 2.0f;
    float y1 = 1.0f - (float)((rectPoints.origin.y + rectPoints.size.height) / screenSize.height) * 2.0f;
    float u0 = uvRect.origin.x, u1 = uvRect.origin.x + uvRect.size.width;
    float v0 = uvRect.origin.y, v1 = uvRect.origin.y + uvRect.size.height;
    float verts[] = {
        x0, y0, u0, v0,   x1, y0, u1, v0,   x0, y1, u0, v1,
        x1, y0, u1, v0,   x1, y1, u1, v1,   x0, y1, u0, v1,
    };
    return [NSData dataWithBytes:verts length:sizeof(verts)];
}

- (void)loadMenuAssets {
    if (_scTexture && _joymaniaTexture) return;
    _scTexture = [self loadXPKTexture:@"maps\\sc.dds"];
    _joymaniaTexture = [self loadXPKTexture:@"maps\\joymania.dds"];
    [self rebuildMenuSpriteBuffers];
}

- (void)rebuildMenuSpriteBuffers {
    CGSize ds = self.drawableSize;
    if (ds.width <= 0) ds = self.bounds.size;
    CGFloat scale = ds.width / fmaxf(self.bounds.size.width, 1.0f); // points -> pixels

    // maps\sc.dds: banner+title occupy UV u[0,0.8945] v[0,0.5] (measured from
    // the file's own alpha channel). Placed top-left-ish, width-driven, with
    // the texture's own 1.785:1 aspect ratio preserved.
    if (_scTexture) {
        CGFloat w = self.bounds.size.width * 0.62f;
        CGFloat h = w * (256.0f / 457.0f);
        CGRect r = CGRectMake(self.bounds.size.width * 0.03f, self.bounds.size.height * 0.02f, w, h);
        NSData *d = [self buildSpriteQuadInRect:r uv:CGRectMake(0, 0, 0.8945, 0.5) screenSize:self.bounds.size];
        _scVertexBuffer = [_device newBufferWithBytes:d.bytes length:d.length options:MTLResourceStorageModeShared];
        _scVertexCount = 6;
    }
    // maps\joymania.dds: logo text block is UV u[0.0156,0.9844] v[0.0234,0.2461]
    // (the same texture also has an unrelated gold figurine lower down, excluded).
    if (_joymaniaTexture) {
        CGFloat w = self.bounds.size.width * 0.34f;
        CGFloat h = w * (57.0f / 248.0f);
        CGRect r = CGRectMake(self.bounds.size.width - w - self.bounds.size.width * 0.03f,
                               self.bounds.size.height * 0.93f, w, h);
        NSData *d = [self buildSpriteQuadInRect:r uv:CGRectMake(0.0156, 0.0234, 0.9688, 0.2227) screenSize:self.bounds.size];
        _joymaniaVertexBuffer = [_device newBufferWithBytes:d.bytes length:d.length options:MTLResourceStorageModeShared];
        _joymaniaVertexCount = 6;
    }
    [self rebuildMenuTextBuffers];
}

- (void)rebuildMenuTextBuffers {
    if (!_fontRenderer) return;
    CGSize ds = self.drawableSize;
    if (ds.width <= 0) ds = self.bounds.size;
    NSArray<NSString *> *labels = @[@"START GAME", @"HIGHSCORES", @"OPTIONS", @"QUIT"];
    CGRect rects[4]; [self computeMenuButtonRects:rects];
    for (int i = 0; i < 4; i++) {
        float fontScale = (float)rects[i].size.height * 0.9f * (ds.height / fmaxf(self.bounds.size.height, 1.0f));
        float penX = (float)(rects[i].origin.x * (ds.width / fmaxf(self.bounds.size.width, 1.0f)));
        float penY = (float)((rects[i].origin.y + rects[i].size.height * 0.8f) * (ds.height / fmaxf(self.bounds.size.height, 1.0f)));
        NSData *verts = [_fontRenderer buildTextVertices:labels[i] atPenX:penX penY:penY
                                                   screenW:ds.width screenH:ds.height scale:fontScale];
        if (verts.length > 0) {
            _menuTextVertexBuffer[i] = [_device newBufferWithBytes:verts.bytes length:verts.length options:MTLResourceStorageModeShared];
            _menuTextVertexCount[i] = (int)(verts.length / (4 * sizeof(float)));
        } else {
            _menuTextVertexCount[i] = 0;
        }
    }
}

// ---------- level view ----------
- (BOOL)loadLevel:(NSString *)levelPath {
    BOOL ok = [_levelRenderer loadLevel:levelPath];
    if (ok) {
        // Same parser LevelRenderer itself uses (GameEngine parseLevelData:) —
        // gives PhysicsWorld the real per-object RADIUS/TYPE/position data.
        NSArray<LevelObject *> *objs = [GameEngine parseLevelData:levelPath];
        [_physicsWorld setEntitiesFromLevelObjects:objs];
        _character.position = simd_make_float3(0, [_physicsWorld groundHeightAtX:0 z:0] + 0.01f, 0);
        _character.velocity = simd_make_float3(0, 0, 0);
        _character.state = CharacterStateIdle;
        _controlsEnabled = YES;
        _btnLeft.hidden = _btnRight.hidden = _btnJump.hidden = NO;
        _lastFrameTime = 0;
        [_levelRenderer loadCharacterMesh:@"gfx\\weihnachtsman_000.x"];
        [self loadMenuAssets];
    } else {
        _controlsEnabled = NO;
        _btnLeft.hidden = _btnRight.hidden = _btnJump.hidden = YES;
    }
    return ok;
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

    // Gameplay step — DINPUT8 replacement. Note: this drives the character's
    // simulation state (position/velocity/state against real level ground +
    // enemy collision) and shows it via the debug text overlay; it does not
    // yet draw a moving Santa mesh inside the level view (LevelRenderer only
    // draws the static placed objects today) — that's the next real step.
    if (_controlsEnabled && levelMode && !_inMainMenu) {
        CFTimeInterval now = CACurrentMediaTime();
        float dt = (_lastFrameTime > 0) ? (float)(now - _lastFrameTime) : 0.0f;
        _lastFrameTime = now;
        dt = fminf(dt, 0.1f); // clamp huge first-frame / stall deltas
        [_character update:dt];
        NSString *stateName[] = {@"Idle", @"Walking", @"Jumping", @"Falling", @"Hurt"};
        NSString *dbg = [NSString stringWithFormat:@"Santa (%.1f, %.1f, %.1f)  %@  ground:%@",
                          _character.position.x, _character.position.y, _character.position.z,
                          stateName[_character.state], _character.isOnGround ? @"Y" : @"N"];
        if (![dbg isEqualToString:_displayText]) [self setTextToDisplay:dbg];
        _showingGameplayDebugText = YES;
    } else if (_showingGameplayDebugText) {
        // Leaving level mode / entering the menu — don't leave stale
        // "Santa (x,y,z) ..." text on screen. AppDelegate's modeChanged:
        // sets its own text right after this for the tab-switch case; this
        // covers the one-frame gap and the menu->play transition too.
        [self setTextToDisplay:@""];
        _showingGameplayDebugText = NO;
    }

    if (_controlsEnabled && levelMode) {
        // Draw Santa in the level at the character's live position — even
        // while still in the main menu (not moving yet, just standing on
        // his spawn platform, same as the PC title screen).
        // NOTE (visual estimate, not a verified constant — see LevelRenderer.h
        // loadCharacterMesh: comment): Santa isn't in data\elements.txt so
        // there's no authored SCALING for him like level objects have; his
        // raw mesh bind-pose is ~129 units tall (measured in tools/test_skin.cpp),
        // so kCharacterScale below is picked to land him around ~2.5 world
        // units tall next to the 3.0-unit level grid — tune this by eye once
        // you can see him next to a platform.
        static const float kCharacterScale = 0.02f;
        float yaw = (_character.facingDirection < 0) ? kPi : 0.0f; // model faces +Z by convention; flip for left
        float c = cosf(yaw) * kCharacterScale, s = sinf(yaw) * kCharacterScale;
        simd_float4x4 charModel = matrix_identity_float4x4;
        charModel.columns[0] = simd_make_float4(c, 0, -s, 0);
        charModel.columns[1] = simd_make_float4(0, kCharacterScale, 0, 0);
        charModel.columns[2] = simd_make_float4(s, 0, c, 0);
        charModel.columns[3] = simd_make_float4(_character.position.x, _character.position.y, _character.position.z, 1.0f);
        _levelRenderer.characterTransform = charModel;
        _levelRenderer.hasCharacter = YES;
    } else {
        _levelRenderer.hasCharacter = NO;
    }

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

    // Pass 3: main menu overlay (sc.dds banner/title, joymania.dds corner
    // logo, START GAME/HIGHSCORES/OPTIONS/QUIT labels) — same sprite
    // pipeline, drawn last so it's always on top while _inMainMenu.
    if (_inMainMenu && levelMode && _spritePipelineState) {
        [e setRenderPipelineState:_spritePipelineState];
        [e setDepthStencilState:_spriteDepthState];
        [e setCullMode:MTLCullModeNone];
        if (_scTexture && _scVertexBuffer && _scVertexCount > 0) {
            [e setVertexBuffer:_scVertexBuffer offset:0 atIndex:0];
            [e setFragmentTexture:_scTexture atIndex:0];
            [e setFragmentSamplerState:_fontRenderer.sampler atIndex:0];
            [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:_scVertexCount];
        }
        if (_joymaniaTexture && _joymaniaVertexBuffer && _joymaniaVertexCount > 0) {
            [e setVertexBuffer:_joymaniaVertexBuffer offset:0 atIndex:0];
            [e setFragmentTexture:_joymaniaTexture atIndex:0];
            [e setFragmentSamplerState:_fontRenderer.sampler atIndex:0];
            [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:_joymaniaVertexCount];
        }
        if (_fontRenderer.atlasTexture) {
            [e setFragmentTexture:_fontRenderer.atlasTexture atIndex:0];
            [e setFragmentSamplerState:_fontRenderer.sampler atIndex:0];
            for (int i = 0; i < 4; i++) {
                if (_menuTextVertexBuffer[i] && _menuTextVertexCount[i] > 0) {
                    [e setVertexBuffer:_menuTextVertexBuffer[i] offset:0 atIndex:0];
                    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:_menuTextVertexCount[i]];
                }
            }
        }
    }

    [e endEncoding];
    [cb presentDrawable:view.currentDrawable];
    [cb commit];
}

@end
