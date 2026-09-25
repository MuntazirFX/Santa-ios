#import <Foundation/Foundation.h>
#import <simd/simd.h>

// ============================================================
// Level Loader
//
// Loads a level .dat file from XPK, resolves each entity's
// mesh + texture via the elements.txt catalog.
//
// Current status: SKELETON
// - Load level entities
// - Expose list for rendering
// ============================================================

@class MeshData;

@interface LevelEntity : NSObject
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSString *type;    // ENEMY, PLATTFORM, DECO...
@property (strong, nonatomic) NSString *meshFile;
@property (nonatomic) simd_float3 position;
@property (nonatomic) simd_float3 rotation;
@property (nonatomic) int32_t variant;
@end

@interface LevelLoader : NSObject

// Load a level from XPK (e.g., "levels\\001.dat")
- (BOOL)loadLevel:(NSString *)levelPath;

// Expose loaded entities
@property (readonly) NSArray<LevelEntity *> *entities;

// Metadata
@property (readonly) NSString *currentLevelName;
@property (readonly) NSUInteger entityCount;

@end
