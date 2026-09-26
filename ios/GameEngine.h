#import <Foundation/Foundation.h>

@interface MeshData : NSObject
@property (nonatomic) int vertexCount;
@property (nonatomic) int faceCount;
@property (strong, nonatomic) NSMutableData *vertices;
@property (strong, nonatomic) NSMutableData *indices;
@property (strong, nonatomic) NSMutableData *uvs;
@property (strong, nonatomic) NSMutableData *colors;
@property (nonatomic) NSUInteger offset;
@property (strong, nonatomic) NSString *textureName;
@property (strong, nonatomic) NSString *debugInfo;
@end

@interface LevelObject : NSObject
@property (strong, nonatomic) NSString *objectName;
@property (nonatomic) float x, y, z;
// Second float triplet from the level record — position of a linked/second
// point for movers & elevators in some element types, rotation for others;
// exact per-type meaning isn't confirmed yet, exposed as raw values.
@property (nonatomic) float extra1, extra2, extra3;
@property (nonatomic) int32_t variant;
// Resolved via the data/elements.txt catalog (ELEMENT "objectName" { FILE "..." }).
// Always a .x model path (".ani" entries are mapped to the matching .x).
@property (strong, nonatomic) NSString *meshFile;
@property (strong, nonatomic) NSString *elementType; // e.g. ENEMY, RECTFORM, PLATTFORM, DECO, BONUS, EXIT...
// RADIUS from the same elements.txt entry (0 if the entry had none) — the
// original exe's own per-element collision radius field. Used by
// PhysicsWorld for ground footprint / enemy-collision checks.
@property (nonatomic) float radius;
@end

@interface GameEngine : NSObject
+ (NSData *)loadAssetNamed:(NSString *)name;
+ (MeshData *)extractMeshFromAsset:(NSString *)assetName;
+ (NSArray<LevelObject *> *)parseLevelData:(NSString *)levelPath;
+ (NSString *)listLevelFiles;
+ (NSString *)listTextureFiles;  // ✅ Yeh wapas add kiya
+ (NSData *)loadTextureRGBA8Named:(NSString *)xpkPath
                             width:(int *)outWidth
                            height:(int *)outHeight;
// Parses data/elements.txt (the ELEMENT catalog) into name -> mesh-file /
// element-type info, used by parseLevelData: to resolve each placed
// object's actual .x model and behavior category.
+ (NSDictionary<NSString *, NSArray<NSString *> *> *)loadElementCatalog;
@end
