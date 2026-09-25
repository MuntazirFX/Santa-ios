#import "Button.h"

@implementation Button

- (instancetype)initWithID:(NSString *)buttonID
                     label:(NSString *)label
                  position:(simd_float2)pos
                      size:(simd_float2)size {
    self = [super init];
    if (self) {
        _buttonID = buttonID;
        _label = label;
        _position = pos;
        _size = size;
        _isPressed = NO;
    }
    return self;
}

- (BOOL)hitTest:(simd_float2)screenPos {
    return screenPos.x >= _position.x &&
           screenPos.x <= _position.x + _size.x &&
           screenPos.y >= _position.y &&
           screenPos.y <= _position.y + _size.y;
}

- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                screenSize:(CGSize)size {
    // TODO: Render button texture from gui2.dds
    // For now, no-op (just text label will be rendered separately)
}

@end
