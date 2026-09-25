#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@interface FontChar : NSObject
@property (nonatomic) int code;
@property (nonatomic) float u0, v0, u1, v1;
@property (nonatomic) float offsetX, advance, offsetY;
@end

@interface FontRenderer : NSObject

// Create with a Metal device
- (instancetype)initWithDevice:(id<MTLDevice>)device;

// Load font from XPK (e.g., "gui\\big_font.txt")
// Also loads the texture atlas from "maps\\big_font00.dds"
- (BOOL)loadFontFromXPK:(NSString *)fontPath;

// Build a vertex buffer for a text string.
// 'scale' is the on-screen height, in PIXELS, of one line of text (em size).
// Returns: 6 vertices per character (two triangles, draw as TRIANGLE LIST).
// Each vertex = (ndcX, ndcY, u, v) floats.
- (NSData *)buildTextVertices:(NSString *)text
                      atPenX:(float)penX
                        penY:(float)penY
                     screenW:(float)screenW
                     screenH:(float)screenH
                       scale:(float)scale;

// Total width of a text string (for centering)
- (float)textWidth:(NSString *)text scale:(float)scale;   // same units as buildTextVertices: scale

// Expose texture atlas
@property (readonly) id<MTLTexture> atlasTexture;
@property (readonly) id<MTLSamplerState> sampler;
@property (readonly) int atlasW;
@property (readonly) int atlasH;

@end
