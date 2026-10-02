#import "AppDelegate.h"
#import "GameEngine.h"
#import "MetalView.h"
#import "BuildInfo.h"

@interface AppDelegate ()
@property (strong, nonatomic) MetalView *metalView;
@property (strong, nonatomic) UITextView *logView;
@end

@implementation AppDelegate

// Level | Santa | Log
- (void)modeChanged:(UISegmentedControl *)seg {
    NSInteger i = seg.selectedSegmentIndex;
    self.metalView.showLevel = (i == 0);
    self.logView.hidden = (i != 2);
    [self.metalView setTextToDisplay:(i == 1) ? @"Santa Claus in Trouble" : @""];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor blackColor];
    
    MetalView *mv = [[MetalView alloc] initWithFrame:vc.view.bounds];
    mv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:mv];
    
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 40, vc.view.bounds.size.width, 260)];
    tv.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont fontWithName:@"Courier" size:9];
    tv.editable = NO;
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [vc.view addSubview:tv];
    self.metalView = mv;
    self.logView = tv;
    
    NSMutableString *log = [NSMutableString string];
    
    [log appendFormat:@"Build: %s @ %s\n\n", SANTA_BUILD_SHA, SANTA_BUILD_TIME];
    
    [log appendString:@"Loading Santa...\n"];
    MeshData *mesh = [GameEngine extractMeshFromAsset:@"gfx\\weihnachtsman_000.x"];
    
    if (mesh && mesh.vertexCount > 0) {
        [log appendFormat:@"✅ SANTA LOADED\n%@\n", mesh.debugInfo ?: @""];
        [mv setMeshToRender:mesh];
        [log appendFormat:@"\n[Texture Debug] %@\n", mv.textureDebugInfo];
    } else {
        [log appendString:@"❌ Santa load failed\n"];
    }
    
    // Bitmap font from the XPK (gui\big_font.txt + maps\big_font00.dds)
    if ([mv loadFont:@"gui\\big_font.txt"]) {
        [mv setTextToDisplay:@"Santa Claus in Trouble"];
        [log appendString:@"\n✅ Font loaded\n"];
    } else {
        [log appendString:@"\n❌ Font load failed\n"];
    }
    
    // Whole level: levels\000.dat -> catalog -> models + textures
    BOOL levelOK = [mv loadLevel:@"levels\\000.dat"];
    if (levelOK) {
        [log appendFormat:@"\n✅ LEVEL LOADED\n%@\n", mv.levelSummary];
    } else {
        [log appendFormat:@"\n❌ Level load failed: %@\n", mv.levelSummary];
    }
    
    [log appendString:@"\nLevels:\n"];
    [log appendString:[GameEngine listLevelFiles]];
    
    [log appendString:@"\nTextures:\n"];
    [log appendString:[GameEngine listTextureFiles]];
    
    tv.text = log;
    
    // Mode switch (top centre): Level / Santa / Log
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Level", @"Santa", @"Log"]];
    seg.frame = CGRectMake((vc.view.bounds.size.width - 230) / 2, 8, 230, 30);
    seg.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    seg.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor blackColor]} forState:UIControlStateSelected];
    seg.selectedSegmentIndex = levelOK ? 0 : 1;
    [seg addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [vc.view addSubview:seg];
    [self modeChanged:seg];
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
