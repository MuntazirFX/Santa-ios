#import "GameState.h"

@implementation GameState

// ✅ Explicit synthesis — auto-synthesis issues avoid karne ke liye
@synthesize currentState = _currentState;
@synthesize currentLevelIndex = _currentLevelIndex;
@synthesize score = _score;
@synthesize lives = _lives;

+ (instancetype)sharedInstance {
    static GameState *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GameState alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentState = GameStateMenu;
        _currentLevelIndex = 0;
        _score = 0;
        _lives = 3;
    }
    return self;
}

- (void)transitionTo:(GameStateType)newState {
    if (_currentState == newState) return;
    
    NSLog(@"[GameState] %ld → %ld", (long)_currentState, (long)newState);
    _currentState = newState;
}

- (BOOL)isState:(GameStateType)state {
    return _currentState == state;
}

- (void)update:(float)deltaTime {
    switch (_currentState) {
        case GameStateMenu:
            break;
        case GameStatePlaying:
            break;
        default:
            break;
    }
}

- (void)startNewGame {
    _score = 0;
    _lives = 3;
    _currentLevelIndex = 0;
    [self transitionTo:GameStatePlaying];
}

- (void)nextLevel {
    _currentLevelIndex++;
    [self transitionTo:GameStatePlaying];
}

- (void)gameOver {
    [self transitionTo:GameStateGameOver];
}

@end
