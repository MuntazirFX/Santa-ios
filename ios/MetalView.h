#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

@class MeshData;

@interface MetalView : MTKView <MTKViewDelegate, UIGestureRecognizerDelegate>

- (instancetype)initWithFrame:(CGRect)frame;
- (void)setMeshToRender:(MeshData *)mesh;

// Font loading from XPK
- (BOOL)loadFont:(NSString *)fontPath;
- (void)setTextToDisplay:(NSString *)text;

// Whole-level view (levels\NNN.dat). Gestures: 1 finger = pan, pinch = zoom,
// 2 finger twist = rotate camera.
- (BOOL)loadLevel:(NSString *)levelPath;
@property (nonatomic) BOOL showLevel;                    // YES = level, NO = single mesh (Santa)
@property (strong, nonatomic, readonly) NSString *levelSummary;

// ---------- Play mode: real movement + collision ----------
// YES = the level's Santa is a live, controllable character (real ground
// collision from PhysicsWorld, gravity, jump) instead of a static bind-pose
// prop, and the camera follows him. Requires showLevel = YES and a level
// already loaded; has no effect otherwise.
@property (nonatomic) BOOL playMode;
// Called every frame (0..1 magnitude each axis) by whatever drives movement
// — e.g. VirtualJoystickView. World-space ground-plane axes, same
// convention as CharacterController.setMoveDirectionX:z:.
- (void)setPlayerMoveX:(float)dx z:(float)dz;
- (void)triggerPlayerJump;
// Lives remaining, for a simple on-screen HUD; -1 if Play mode has never
// been entered (no character exists yet).
@property (nonatomic, readonly) int playerLives;

@property (strong, nonatomic) NSString *textureDebugInfo;

@end
