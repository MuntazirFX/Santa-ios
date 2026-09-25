#import "AudioEngine.h"
#import <AVFoundation/AVFoundation.h>
#include "AssetManager.h"
#include <vector>
#include <map>

@implementation AudioEngine {
    NSMutableDictionary<NSString *, AVAudioPlayer *> *_players;
}

+ (instancetype)sharedInstance {
    static AudioEngine *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[AudioEngine alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _players = [NSMutableDictionary dictionary];
        
        // Configure audio session
        NSError *err = nil;
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:&err];
        [[AVAudioSession sharedInstance] setActive:YES error:&err];
    }
    return self;
}

- (BOOL)loadSoundsFromXPK {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) {
        NSLog(@"[Audio] xmas.xpk not found");
        return NO;
    }
    
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) {
        NSLog(@"[Audio] XPK load failed");
        return NO;
    }
    
    // SFX names from sfx.txt catalog
    NSArray<NSString *> *sfxNames = @[
        @"klick", @"present", @"jumper01", @"jump01", @"snow01",
        @"dying01", @"score", @"goblin01", @"goblin02", @"goblin03",
        @"crow01", @"crow02", @"crow03", @"waypoint", @"extralife"
    ];
    
    int loaded = 0;
    for (NSString *name in sfxNames) {
        std::string path = "sfx\\" + std::string([name UTF8String]) + ".wav";
        std::vector<uint8_t> data = am.getAssetData(path);
        if (data.empty()) {
            NSLog(@"[Audio] Not found: %@", name);
            continue;
        }
        
        NSData *wavData = [NSData dataWithBytes:data.data() length:data.size()];
        NSError *err = nil;
        AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:wavData error:&err];
        if (player) {
            [player prepareToPlay];
            _players[name] = player;
            loaded++;
        }
    }
    
    NSLog(@"[Audio] Loaded %d/%lu sounds", loaded, (unsigned long)sfxNames.count);
    return loaded > 0;
}

- (void)playSound:(NSString *)soundName {
    [self playSound:soundName volume:1.0f];
}

- (void)playSound:(NSString *)soundName volume:(float)volume {
    AVAudioPlayer *player = _players[soundName];
    if (!player) return;
    
    player.volume = volume;
    player.currentTime = 0;
    [player play];
}

- (void)stopAll {
    for (AVAudioPlayer *p in _players.allValues) {
        [p stop];
    }
}

@end
