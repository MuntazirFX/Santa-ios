#import <Foundation/Foundation.h>

// ============================================================
// Audio Engine
//
// Plays .wav sound effects from XPK archive.
//
// Current status: SKELETON
// - Load and play WAV from bundle/XPK
// - Uses AVAudioPlayer (simple, no 3D positioning yet)
// ============================================================

@interface AudioEngine : NSObject

+ (instancetype)sharedInstance;

// Preload all SFX (reads sfx.txt catalog)
- (BOOL)loadSoundsFromXPK;

// Play a sound by ID (e.g., "jump01", "klick")
- (void)playSound:(NSString *)soundName;

// Play with volume (0.0 - 1.0)
- (void)playSound:(NSString *)soundName volume:(float)volume;

// Stop all sounds
- (void)stopAll;

@end
