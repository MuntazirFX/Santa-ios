#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

// ============================================================
// Button
//
// A clickable UI element with label, position, and size.
// ============================================================

@interface Button : NSObject

@property (strong, nonatomic) NSString *buttonID;  // e.g. "start_game"
@property (strong, nonatomic) NSString *label;      // e.g. "START GAME"
@property (nonatomic) simd_float2 position;         // top-left in points
@property (nonatomic) simd_float2 size;             // in points
@property (nonatomic) BOOL isPressed;

- (instancetype)initWithID:(NSString *)buttonID
                     label:(NSString *)label
                  position:(simd_float2)pos
                      size:(simd_float2)size;

// Check if a screen point hits this button
- (BOOL)hitTest:(simd_float2)screenPos;

// Render placeholder (for now, just a colored quad)
- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                screenSize:(CGSize)size;

@end
