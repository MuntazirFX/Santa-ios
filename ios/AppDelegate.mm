#import "AppDelegate.h"
#import "GameEngine.h"
#import "MetalView.h"
#import "BuildInfo.h"
#import "VirtualJoystick.h"

@interface AppDelegate ()
@property (strong, nonatomic) MetalView *metalView;
@property (strong, nonatomic) UITextView *logView;
@property (strong, nonatomic) VirtualJoystickView *joystickView;
@property (strong, nonatomic) UIButton *jumpButton;
@property (strong, nonatomic) UILabel *livesLabel;
@property (strong, nonatomic) NSTimer *hudTimer;
@end

@implementation AppDelegate

// Level | Santa | Play | Log
- (void)modeChanged:(UISegmentedControl *)seg {
    NSInteger i = seg.selectedSegmentIndex;
    BOOL playing = (i == 2);
    self.metalView.showLevel = (i == 0 || i == 2);
    self.metalView.playMode = playing;
    self.logView.hidden = (i != 3);
    self.joystickView.hidden = !playing;
    self.jumpButton.hidden = !playing;
    self.livesLabel.hidden = !playing;
    [self.metalView setTextToDisplay:(i == 1) ? @"Santa Claus in Trouble" : @""];
}

- (void)jumpPressed {
    [self.metalView triggerPlayerJump];
}

- (void)updateHUD {
    if (self.livesLabel.hidden) return;
    int lives = self.metalView.playerLives;
    self.livesLabel.text = (lives >= 0) ? [NSString stringWithFormat:@"♥ %d", lives] : @"";
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
    
    // Mode switch (top centre): Level / Santa / Play / Log
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Level", @"Santa", @"Play", @"Log"]];
    seg.frame = CGRectMake((vc.view.bounds.size.width - 280) / 2, 8, 280, 30);
    seg.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    seg.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor blackColor]} forState:UIControlStateSelected];
    seg.selectedSegmentIndex = levelOK ? 0 : 1;
    [seg addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [vc.view addSubview:seg];

    // Play-mode controls: bottom-left joystick (move), bottom-right button
    // (jump). Separate UIViews so they never compete with the level's
    // pan/pinch/rotate camera gestures on MetalView.
    CGFloat pad = 24, jsSize = 120, jumpSize = 76;
    CGFloat vh = vc.view.bounds.size.height, vw = vc.view.bounds.size.width;
    VirtualJoystickView *joystick = [[VirtualJoystickView alloc] initWithFrame:CGRectMake(pad, vh - jsSize - pad - 20, jsSize, jsSize)];
    joystick.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    __weak MetalView *weakMV = mv;
    joystick.onMove = ^(float dx, float dz) { [weakMV setPlayerMoveX:dx z:dz]; };
    [vc.view addSubview:joystick];
    self.joystickView = joystick;

    UIButton *jump = [UIButton buttonWithType:UIButtonTypeSystem];
    jump.frame = CGRectMake(vw - jumpSize - pad, vh - jumpSize - pad - 20, jumpSize, jumpSize);
    jump.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
    jump.layer.cornerRadius = jumpSize / 2.0;
    jump.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    jump.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    jump.layer.borderWidth = 1.5;
    [jump setTitle:@"JUMP" forState:UIControlStateNormal];
    [jump setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [jump addTarget:self action:@selector(jumpPressed) forControlEvents:UIControlEventTouchDown];
    [vc.view addSubview:jump];
    self.jumpButton = jump;

    UILabel *lives = [[UILabel alloc] initWithFrame:CGRectMake(pad, 48, 100, 30)];
    lives.textColor = [UIColor whiteColor];
    lives.font = [UIFont boldSystemFontOfSize:20];
    lives.text = @"";
    [vc.view addSubview:lives];
    self.livesLabel = lives;
    self.hudTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(updateHUD) userInfo:nil repeats:YES];

    [self modeChanged:seg];

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
