#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

// ============================================================
// UI Manager
//
// Manages 2D UI elements: buttons, text, backgrounds.
//
// Current status: SKELETON
// - Button list
// - Render into Metal encoder
// ============================================================

@class Button;

@interface UIManager : NSObject

// Add a button at a screen position (points)
- (void)addButton:(Button *)button;

// Remove all
- (void)clear;

// Update with touch event
- (void)handleTouchAt:(simd_float2)screenPos;

// Draw all UI to given Metal encoder
- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                screenSize:(CGSize)size;

// Check if any button was pressed this frame
@property (readonly) NSString *lastPressedButtonID;

@end
