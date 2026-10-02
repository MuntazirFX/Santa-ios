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

@property (strong, nonatomic) NSString *textureDebugInfo;

@end
