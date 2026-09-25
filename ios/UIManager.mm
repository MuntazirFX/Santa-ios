#import "UIManager.h"
#import "Button.h"

@implementation UIManager {
    NSMutableArray<Button *> *_buttons;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _buttons = [NSMutableArray array];
        _lastPressedButtonID = nil;
    }
    return self;
}

- (void)addButton:(Button *)button {
    if (button) [_buttons addObject:button];
}

- (void)clear {
    [_buttons removeAllObjects];
}

- (void)handleTouchAt:(simd_float2)screenPos {
    _lastPressedButtonID = nil;
    for (Button *b in _buttons) {
        if ([b hitTest:screenPos]) {
            _lastPressedButtonID = b.buttonID;
            NSLog(@"[UI] Button pressed: %@", b.buttonID);
            break;
        }
    }
}

- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                screenSize:(CGSize)size {
    // TODO: Render each button's texture/quad
    for (Button *b in _buttons) {
        [b renderWithEncoder:encoder screenSize:size];
    }
}

@end
