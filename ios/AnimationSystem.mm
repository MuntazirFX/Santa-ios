#import "AnimationSystem.h"
#include "AssetManager.h"
#include "AniParser.h"
#include <vector>

@implementation AnimationClip
@end

@implementation AnimationSystem {
    std::vector<AniClip> _clipsCpp;
    int _currentClipIdx;
    float _currentTime;
    BOOL _playing;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _clipsCpp.clear();
        _currentClipIdx = -1;
        _currentTime = 0;
        _playing = NO;
        _clips = @[];
    }
    return self;
}

- (BOOL)loadFromXPK:(NSString *)aniPath {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) {
        NSLog(@"[Anim] xmas.xpk not found");
        return NO;
    }
    
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) {
        NSLog(@"[Anim] XPK load failed");
        return NO;
    }
    
    std::vector<uint8_t> fileData = am.getAssetData([aniPath UTF8String]);
    if (fileData.empty()) {
        NSLog(@"[Anim] File not found: %@", aniPath);
        return NO;
    }
    
    NSLog(@"[Anim] Loaded file: %lu bytes", (unsigned long)fileData.size());
    
    // .ani data is stored RAW (not MSZIP like .x) — decompress() is a passthrough.
    std::vector<uint8_t> decompressed = AniParser::decompress(fileData.data(), fileData.size());
    NSLog(@"[Anim] Raw data: %lu bytes", (unsigned long)decompressed.size());
    
    // Parse clips
    _clipsCpp = AniParser::parse(decompressed.data(), decompressed.size());
    NSLog(@"[Anim] Clips parsed: %lu", (unsigned long)_clipsCpp.size());
    
    // Wrap in ObjC objects
    NSMutableArray<AnimationClip *> *arr = [NSMutableArray array];
    for (size_t i = 0; i < _clipsCpp.size(); i++) {
        AnimationClip *clip = [[AnimationClip alloc] init];
        clip.clipIndex = (int)i;
        clip.name = [NSString stringWithUTF8String:_clipsCpp[i].name.c_str()];
        clip.duration = _clipsCpp[i].duration;
        clip.boneCount = (int)_clipsCpp[i].tracks.size();
        [arr addObject:clip];
    }
    _clips = arr;
    
    return YES;
}

- (void)playClip:(int)clipIndex {
    if (clipIndex < 0 || clipIndex >= (int)_clipsCpp.size()) return;
    _currentClipIdx = clipIndex;
    _currentTime = 0;
    _playing = YES;
    NSLog(@"[Anim] Playing clip %d: '%s'", clipIndex, _clipsCpp[clipIndex].name.c_str());
}

- (void)stop {
    _playing = NO;
    _currentTime = 0;
}

- (void)update:(float)deltaTime {
    if (!_playing || _currentClipIdx < 0) return;
    
    _currentTime += deltaTime;
    float duration = _clipsCpp[_currentClipIdx].duration;
    if (duration > 0) {
        while (_currentTime >= duration) _currentTime -= duration;
    }
    
    // TODO: Apply bone transforms from current clip at _currentTime
}

- (int)currentClipIndex {
    return _currentClipIdx;
}

- (float)currentTime {
    return _currentTime;
}

- (BOOL)isPlaying {
    return _playing;
}

@end
