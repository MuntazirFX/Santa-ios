#import <Foundation/Foundation.h>

// ============================================================
// Game State Machine
//
// Controls which screen/mode the game is in.
// ============================================================

typedef NS_ENUM(NSInteger, GameStateType) {
    GameStateMenu = 0,
    GameStateLoading = 1,
    GameStatePlaying = 2,
    GameStatePaused = 3,
    GameStateGameOver = 4,
    GameStateLevelComplete = 5
};

@interface GameState : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic) GameStateType currentState;
@property (nonatomic) int currentLevelIndex;
@property (nonatomic) int score;
@property (nonatomic) int lives;

- (void)transitionTo:(GameStateType)newState;
- (BOOL)isState:(GameStateType)state;
- (void)update:(float)deltaTime;
- (void)startNewGame;
- (void)nextLevel;
- (void)gameOver;

@end
