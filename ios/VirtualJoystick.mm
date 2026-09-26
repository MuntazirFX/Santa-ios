#import "VirtualJoystick.h"
#import <QuartzCore/QuartzCore.h>

@implementation VirtualJoystickView {
    CAShapeLayer *_base;
    CAShapeLayer *_knob;
    CGPoint _center;
    CGFloat _radius;
    UITouch *_activeTouch;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.multipleTouchEnabled = NO;
        _radius = MIN(frame.size.width, frame.size.height) * 0.5f;
        _center = CGPointMake(frame.size.width * 0.5f, frame.size.height * 0.5f);

        _base = [CAShapeLayer layer];
        _base.path = [UIBezierPath bezierPathWithOvalInRect:self.bounds].CGPath;
        _base.fillColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
        _base.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        _base.lineWidth = 1.5;
        [self.layer addSublayer:_base];

        CGFloat kr = _radius * 0.42f;
        _knob = [CAShapeLayer layer];
        _knob.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(_center.x - kr, _center.y - kr, kr * 2, kr * 2)].CGPath;
        _knob.fillColor = [UIColor colorWithWhite:1.0 alpha:0.55].CGColor;
        [self.layer addSublayer:_knob];
    }
    return self;
}

- (void)moveKnobTo:(CGPoint)p {
    CGFloat kr = _radius * 0.42f;
    _knob.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(p.x - kr, p.y - kr, kr * 2, kr * 2)].CGPath;
}

- (void)reportDX:(float)dx dz:(float)dz {
    if (self.onMove) self.onMove(dx, dz);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_activeTouch) return;
    _activeTouch = touches.anyObject;
    [self updateWithTouch:_activeTouch];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (![touches containsObject:_activeTouch]) return;
    [self updateWithTouch:_activeTouch];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (![touches containsObject:_activeTouch]) return;
    _activeTouch = nil;
    [self moveKnobTo:_center];
    [self reportDX:0 dz:0];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

- (void)updateWithTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self];
    CGFloat vx = p.x - _center.x;
    CGFloat vy = p.y - _center.y;
    CGFloat len = sqrt(vx * vx + vy * vy);
    CGFloat maxLen = _radius * 0.9f;
    if (len > maxLen && len > 0.0001f) { vx = vx / len * maxLen; vy = vy / len * maxLen; len = maxLen; }
    [self moveKnobTo:CGPointMake(_center.x + vx, _center.y + vy)];
    // Screen: +x right, +y down. Ground plane: dx = right, dz = "up on
    // screen" = forward, so screen-down (+y) means dz negative.
    float dx = maxLen > 0 ? (float)(vx / maxLen) : 0.0f;
    float dz = maxLen > 0 ? (float)(-vy / maxLen) : 0.0f;
    [self reportDX:dx dz:dz];
}

@end
