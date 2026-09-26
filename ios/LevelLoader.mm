#import "LevelLoader.h"
#include "AssetManager.h"
#include "LevelParser.h"
#include "ElementCatalog.h"
#include <string>
#include <vector>

@implementation LevelEntity
@end

@implementation LevelLoader {
    std::vector<LevelEntity *> _entitiesCpp;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entitiesCpp.clear();
        _entities = @[];
        _currentLevelName = @"";
        _entityCount = 0;
    }
    return self;
}

- (BOOL)loadLevel:(NSString *)levelPath {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) {
        NSLog(@"[Level] xmas.xpk not found");
        return NO;
    }
    
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) {
        NSLog(@"[Level] XPK load failed");
        return NO;
    }
    
    std::vector<uint8_t> fileData = am.getAssetData([levelPath UTF8String]);
    if (fileData.empty()) {
        NSLog(@"[Level] File not found: %@", levelPath);
        return NO;
    }
    
    NSLog(@"[Level] Loaded: %@ (%lu bytes)", levelPath, (unsigned long)fileData.size());
    
    // Load data/elements.txt once — it is the authoritative source for each
    // object's model file and TYPE (ENEMY, RECTFORM, PLATTFORM, ...).
    ElementCatalog &catalog = ElementCatalog::shared();
    if (catalog.size() == 0) {
        std::vector<uint8_t> catBytes = am.getAssetData("data\\elements.txt");
        catalog.parse(std::string(catBytes.begin(), catBytes.end()));
        NSLog(@"[Level] element catalog: %lu entries", (unsigned long)catalog.size());
    }
    
    LevelData ld = LevelParser::parse(fileData.data(), fileData.size());
    
    NSMutableArray<LevelEntity *> *arr = [NSMutableArray array];
    for (const auto& e : ld.entities) {
        LevelEntity *le = [[LevelEntity alloc] init];
        le.name = [NSString stringWithUTF8String:e.name.c_str()];
        le.type = [NSString stringWithUTF8String:LevelParser::getEntityType(e.name).c_str()];
        const ElementDef *def = catalog.find(e.name);
        if (def && !def->meshFile.empty()) {
            le.meshFile = [NSString stringWithUTF8String:def->meshFile.c_str()];
        }
        le.position = simd_make_float3(e.x, e.y, e.z);
        le.rotation = simd_make_float3(e.rotX, e.rotY, e.rotZ);
        le.variant = e.variant;
        [arr addObject:le];
    }
    
    _entities = arr;
    _currentLevelName = levelPath;
    _entityCount = arr.count;
    
    NSLog(@"[Level] %lu entities loaded", (unsigned long)_entityCount);
    return YES;
}

@end
