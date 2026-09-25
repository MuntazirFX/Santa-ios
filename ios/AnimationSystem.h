#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

// ============================================================
// Animation System (iOS layer)
//
// Uses AniParser (C++) internally to load .ani files.
// Manages playback state for skinned character animations.
//
// Current status: SKELETON
// - Load and hold clip data
// - Expose current clip/time
// - Apply bone transforms (TODO: needs skinning support)
// ============================================================

@class MeshData;

@interface AnimationClip : NSObject
@property (nonatomic) int clipIndex;
@property (strong, nonatomic) NSString *name;
@property (nonatomic) float duration;
@property (nonatomic) int boneCount;
@end

@interface AnimationSystem : NSObject

// Load .ani file from XPK (e.g., "gfx\\weihnachtsman_000.ani")
- (BOOL)loadFromXPK:(NSString *)aniPath;

// Currently loaded clips
@property (readonly) NSArray<AnimationClip *> *clips;

// Playback control
- (void)playClip:(int)clipIndex;
- (void)stop;
- (void)update:(float)deltaTime;

// State
@property (readonly) int currentClipIndex;
@property (readonly) float currentTime;
@property (readonly) BOOL isPlaying;

@end
