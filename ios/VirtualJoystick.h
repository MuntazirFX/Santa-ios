#import <UIKit/UIKit.h>

// ============================================================
// VirtualJoystickView — bottom-left drag pad for Play-mode movement.
//
// A separate UIView (not a gesture recognizer on MetalView) so it never
// competes with the level's pan/pinch/rotate camera gestures: touches
// landing inside this view's own frame go to it, everything else still
// reaches MetalView exactly as before.
// ============================================================
@interface VirtualJoystickView : UIView

// dx/dz in -1..1 (screen-right = +x, screen-up = +z, matching the ground
// plane's forward axis used elsewhere), called continuously while
// dragged and once more with (0,0) on release.
@property (nonatomic, copy) void (^onMove)(float dx, float dz);

@end
