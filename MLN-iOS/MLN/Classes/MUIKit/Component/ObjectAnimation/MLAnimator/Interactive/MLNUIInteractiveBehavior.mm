//
//  MLNUIInteractiveBehavior.m
//  ArgoUI
//
//  Created by MOMO on 2020/6/18.
//

#import "MLNUIInteractiveBehavior.h"
#import "UIView+MLNUIKit.h"
#import "MLAAnimation.h"
#import "MLAValueAnimation+Interactive.h"
#import "MLNUIPinchGestureRecognizer.h"

#include "ObjectAnimation.h"
#include "MultiAnimation.h"
#import "MLADefines.h"
#import "MLAAnimatable.h"

#import "MLNUIViewExporterMacro.h"
#import "UIView+MLNUIKit.h"
#import "MLNUIMetamacros.h"

#define MLNUIAnimationPosition  (1 << 0)
#define MLNUIAnimationPositionX (1 << 1)
#define MLNUIAnimationPositionY (1 << 2)
#define MLNUIPositionXMask (MLNUIAnimationPosition | MLNUIAnimationPositionX)
#define MLNUIPositionYMask (MLNUIAnimationPosition | MLNUIAnimationPositionY)

union MLNUIAnimationTypes {
    uintptr_t bits;
    struct {
        uintptr_t position  : 1;
        uintptr_t positionX : 1;
        uintptr_t pssitionY : 1;
    };
};

@interface MLNUIInteractiveBehavior ()

@property (nonatomic, assign) InteractiveType type;
@property (nonatomic, strong) NSHashTable <MLAValueAnimation *> *valueAnimations;
@property (nonatomic, strong) MLNUITouchCallback touchCallback;
@property (nonatomic, strong) MLNUIPinchGestureRecognizer *pinchGesture;
@property (nonatomic, assign) CGPoint beginPoint;
@property (nonatomic, assign) CGPoint endPoint;
@property (nonatomic, assign) CGPoint tolerant;
@property (nonatomic, assign) CGFloat lastDistance;
@property (nonatomic, strong) MLNUIBlock *luaTouchBlock;
@property (nonatomic, assign) MLNUIAnimationTypes animationTypes;

@end

@implementation MLNUIInteractiveBehavior

#pragma mark - Public

- (instancetype)initWithLuaCore:(MLNUILuaCore *)luaCore type:(InteractiveType)type {
    if (self = [super init]) {
        [self setupWithType:type];
    }
    return self;
}

- (void)setTargetView:(UIView *)targetView {
    switch (self.type) {
        case InteractiveType_Gesture:
            [self addTouchActionWithTargetView:targetView];
            break;
            
        case InteractiveType_Scale:
            [self addPinchActionWithTargetView:targetView];
            break;
            
        default:
            break;
    }
    _targetView = targetView;
}

- (void)addAnimation:(MLAValueAnimation *)ani {
    if (ani) {
        [self.valueAnimations addObject:ani];
        if ([ani.valueName isEqualToString:kMLAViewPosition]) {
            _animationTypes.bits |= MLNUIAnimationPosition;
        } else if ([ani.valueName isEqualToString:kMLAViewPositionX]) {
            _animationTypes.bits |= MLNUIAnimationPositionX;
        } else if ([ani.valueName isEqualToString:kMLAViewPositionY]) {
            _animationTypes.bits |= MLNUIAnimationPositionY;
        }
    }
}
- (void)removeAnimation:(MLAValueAnimation *)ani {
    if (ani) {
        [self.valueAnimations removeObject:ani];
        if ([ani.valueName isEqualToString:kMLAViewPosition]) {
            _animationTypes.bits &= ~MLNUIAnimationPosition;
        } else if ([ani.valueName isEqualToString:kMLAViewPositionX]) {
            _animationTypes.bits &= ~MLNUIAnimationPositionX;
        } else if ([ani.valueName isEqualToString:kMLAViewPositionY]) {
            _animationTypes.bits &= ~MLNUIAnimationPositionY;
        }
    }
}

- (void)removeAllAnimations {
    [self.valueAnimations removeAllObjects];
    _animationTypes.bits = 0;
}

#pragma mark - Private

// 若 position 动画方向和手势驱动方向不同，则禁用手势跟随效果
static inline BOOL MLNUIFollowEnable(MLNUIInteractiveBehavior *self) {
    BOOL disallow = NO;
    if (self.direction == InteractiveDirection_X) {
        disallow = self->_animationTypes.bits & MLNUIPositionYMask;
    } else {
        disallow = self->_animationTypes.bits & MLNUIPositionXMask;
    }
    return (self.followEnable && !disallow);
}

static inline CGFloat MLNUIDeltaValueOfTwoPoints(CGPoint point1, CGPoint point2) {
    CGFloat value = pow(abs(point2.x - point1.x), 2) + pow(abs(point2.y - point1.y), 2);
    if (value > 0) {
        return sqrt(value);
    }
    return 0;
}

- (void)setupWithType:(InteractiveType)type {
    _type = type;
    _max = 1999;
    _valueAnimations = [NSHashTable weakObjectsHashTable];
}

- (void)addPinchActionWithTargetView:(UIView *)targetView {
    [self.targetView removeGestureRecognizer:self.pinchGesture];
    if (targetView) {
        [targetView addGestureRecognizer:self.pinchGesture];
    }
}

- (MLNUIPinchGestureRecognizer *)pinchGesture {
    if (!_pinchGesture) {
        _pinchGesture = [[MLNUIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchGestureAction:)];
    }
    return _pinchGesture;
}

- (void)pinchGestureAction:(MLNUIPinchGestureRecognizer *)gesture {
    if (gesture.numberOfTouches < 2) return;
    CGPoint point1 = [gesture locationOfTouch:0 inView:gesture.view.superview];
    CGPoint point2 = [gesture locationOfTouch:1 inView:gesture.view.superview];
    CGFloat delta = MLNUIDeltaValueOfTwoPoints(point1, point2);
    CGFloat factor = (self.max > 0) ? (delta / self.max) : 0;
    
    switch (gesture.argoui_state) {
        case UIGestureRecognizerStateBegan:
            [self onTouch:MLNUITouchType_Begin delta:delta velocity:factor];
            break;
            
        case UIGestureRecognizerStateChanged: {
            BOOL shouldReturn = !self.overBoundary && (factor > 1 || factor < 0);
            if (shouldReturn) return;
            [self onTouch:MLNUITouchType_Move delta:delta velocity:factor];
            for (MLAValueAnimation *ani in self.valueAnimations) {
                [ani updateWithFactor:factor isBegan:NO];
            }
        }
            break;
            
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            [self onTouch:MLNUITouchType_End delta:delta velocity:factor];
            break;
            
        default:
            break;
    }
}

- (void)addTouchActionWithTargetView:(UIView *)targetView {
    __weak __typeof(self) weakSelf = self;
    self.touchCallback = ^(MLNUITouchType type, UITouch *touch, UIEvent * _Nonnull event) {
        [weakSelf handleTouch:touch touchType:type];
    };
    [self.targetView mlnui_removeTouchBlock:self.touchCallback];
    [targetView mlnui_addTouchBlock:self.touchCallback];
}

- (void)handleTouch:(UITouch *)touch touchType:(MLNUITouchType)touchType {
    CGFloat newSpeed,oldSpeed = 0;
    NSTimeInterval previousTime = 0;
    CGFloat lastSpeed = 0;
    if (!self.enable || !self.targetView.superview || self.max == 0) {
        return;
    }
    if (previousTime == touch.timestamp) {
        return;
    }
    CGPoint point = [touch locationInView:self.targetView.superview];
    CGPoint lastPoint = [touch previousLocationInView:self.targetView.superview];
    point = CGPointMake(point.x + self.tolerant.x, point.y + self.tolerant.y);
    lastPoint = CGPointMake(lastPoint.x + self.tolerant.x, lastPoint.y + self.tolerant.y);
    
    CGPoint diffLast = CGPointMake(point.x - lastPoint.x, point.y - lastPoint.y);
    CGPoint diffBegin = CGPointMake(point.x - self.beginPoint.x, point.y - self.beginPoint.y);
    CGFloat dis = self.direction == InteractiveDirection_X ? diffBegin.x : diffBegin.y;
    float factor = dis / self.max;
    const float lambda = 0.8f; // the closer to 1 the higher weight to the next touch
    newSpeed = (1.0 - lambda) * oldSpeed + lambda* ((point.y - lastPoint.y)/(touch.timestamp - previousTime));
    oldSpeed = newSpeed;
    previousTime = touch.timestamp;
    
    switch (touchType) {
        case MLNUITouchType_Begin: {
            if (CGPointEqualToPoint(self.beginPoint, CGPointZero)) {
                self.beginPoint = point;
            }
            if (CGPointEqualToPoint(self.endPoint, CGPointZero)) {
                self.tolerant = CGPointZero;
            } else {
                self.tolerant = CGPointMake(self.endPoint.x - point.x, self.endPoint.y - point.y);
            }
            newSpeed = oldSpeed = lastSpeed = 00;
            [self onTouch:touchType delta:dis velocity:newSpeed];
        }
            break;
            
        case MLNUITouchType_Move: {
            BOOL shouldReturn = !self.overBoundary && (factor > 1 || factor < 0);
            if (!shouldReturn) {
                [self onTouch:touchType delta:dis velocity:newSpeed];
            }
            dispatch_block_t followBlock = ^{
                CGPoint c = self.targetView.center;
                CGPoint newc = CGPointMake(c.x + diffLast.x, c.y + diffLast.y);
                self.targetView.center = newc;
            };
            if (MLNUIFollowEnable(self)) {
                followBlock();
            }
            if (shouldReturn) {
                if ((newSpeed > 0) ^ (lastSpeed > 0)) {
                    lastSpeed = newSpeed;
                    if (factor > 1) {
                        self.beginPoint = CGPointMake(point.x - self.max, point.y - self.max);
                    } else {
                        self.beginPoint = point;
                    }
                }
                return;
            }
            for (MLAValueAnimation *ani in self.valueAnimations) {
                [ani updateWithFactor:factor isBegan:NO];
            }
        }
            break;
            
        case MLNUITouchType_End:
            self.endPoint = point;
            self.tolerant = CGPointZero;
            [self onTouch:touchType delta:dis velocity:newSpeed];
            break;
            
        default:
            break;
    }
    
    lastSpeed = newSpeed;
}

- (void)onTouch:(MLNUITouchType)type delta:(CGFloat)delta velocity:(float)velocity {
    if (self.touchBlock) {
        self.touchBlock(type, delta, velocity);
    }
    if (self.luaTouchBlock) {
        [self.luaTouchBlock addUIntegerArgument:type];
        [self.luaTouchBlock addFloatArgument:delta];
        [self.luaTouchBlock addFloatArgument:velocity];
        [self.luaTouchBlock callIfCan];
    }
    self.lastDistance = delta;
}

#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    MLNUIInteractiveBehavior *beh = [[MLNUIInteractiveBehavior alloc] initWithType:self.type];
    beh.type = self.type;
    beh.direction = self.direction;
    beh.max = self.max;
    beh.overBoundary = self.overBoundary;
    beh.enable = self.enable;
    beh.followEnable = self.followEnable;
    
    beh.targetView = self.targetView;
    beh.valueAnimations = self.valueAnimations.copy;
    beh.touchBlock = self.touchBlock;
    
    return beh;
}

#pragma mark - Lua Bridge

- (instancetype)initWithMLNUILuaCore:(MLNUILuaCore *)luaCore type:(InteractiveType)type {
    if (self = [self initWithMLNUILuaCore:luaCore]) {
        [self setupWithType:type];
    }
    return self;
}

- (void)lua_setTouchBlock:(MLNUIBlock *)block {
    self.luaTouchBlock = block;
}

- (MLNUIBlock *)lua_touchBlock {
    return self.luaTouchBlock;
}

- (void)lua_clearAnimation {
    [self removeAllAnimations];
}

@end
