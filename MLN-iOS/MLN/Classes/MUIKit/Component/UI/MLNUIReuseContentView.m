//
//  MLNUIReuseContentView.m
//
//
//  Created by MoMo on 2018/11/12.
//

#import "MLNUIReuseContentView.h"
#import "MLNUILuaCore.h"
#import "MLNUIKitHeader.h"
#import "UIView+MLNUIKit.h"
#import "UIView+MLNUILayout.h"
#import "MLNUILuaTable.h"

@interface MLNUIReuseContentView()

@property (nonatomic, weak) UIView<MLNUIReuseCellProtocol> *cell;
@property (nonatomic, assign) CGRect oldFrame; // the frame which before MLNUIReuseContentView's content layout change.

@end

@implementation MLNUIReuseContentView

#pragma mark - Public

- (instancetype)initWithFrame:(CGRect)frame cellView:(UIView<MLNUIReuseCellProtocol> *)cell
{
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        _cell = cell;
    }
    return self;
}

- (CGSize)caculateContentViewSizeWithMaxSize:(CGSize)maxSize apply:(BOOL)apply {
    return [self caculateContentViewSizeWithFitSize:CGSizeZero maxSize:maxSize apply:apply];
}

- (CGSize)caculateContentViewSizeWithFitSize:(CGSize)fitSize maxSize:(CGSize)maxSize apply:(BOOL)apply {
    [self setupLayoutNodeFitSize:fitSize maxSize:CGSizeZero];
    if (apply) {
        return [self.mlnui_layoutNode applyLayoutWithSize:maxSize];
    }
    return [self.mlnui_layoutNode calculateLayoutWithSize:maxSize];
}

//- (void)pushToLuaCore:(MLNUILuaCore *)luaCore {
//    [self createLuaTableAsCellNameForLuaIfNeed:luaCore];
//    [self setupLayoutNodeIfNeed];
//    [self updateFrameIfNeed];
//}

// adapter:initCell(function(cell) --[[这里的 cell 便是下面创建的 lua table--]] end)
- (MLNUILuaTable *)createLuaTableAsCellNameForLuaIfNeed:(MLNUILuaCore *)luaCore {
    if (!_luaTable) {
        _luaTable = [[MLNUILuaTable alloc] initWithMLNUILuaCore:luaCore env:MLNUILuaTableEnvRegister];
        [_luaTable setObject:self key:@"contentView"];
    }
    return _luaTable;
}

- (void)createLayoutNodeIfNeedWithFitSize:(CGSize)fitSize maxSize:(CGSize)maxSize {
    [self setupLayoutNodeFitSize:fitSize maxSize:maxSize];
    if (!self.inited) {
        [self mlnui_markNeedsLayout];
        [MLNUI_KIT_INSTANCE(self.mlnui_luaCore) addRootnode:self.mlnui_layoutNode];
    }
}

//- (void)updateFrameIfNeed
//{
//    if (!CGSizeEqualToSize(self.frame.size, self.cell.bounds.size)) {
//        CGRect frame = self.cell.bounds;
//        MLNUILayoutNode *node = self.mlnui_layoutNode;
//        node.marginLeft = MLNUIPointValue(frame.origin.x);
//        node.marginTop = MLNUIPointValue(frame.origin.y);
//        node.width = MLNUIPointValue(frame.size.width);
//        node.height = MLNUIPointValue(frame.size.height);
//    }
//}

#pragma mark - Private

- (void)setupLayoutNodeFitSize:(CGSize)fitSize maxSize:(CGSize)maxSize {
    MLNUILayoutNode *node = [self mlnui_layoutNode];
    node.width = (fitSize.width > 0) ? MLNUIPointValue(fitSize.width) : MLNUIValueAuto;
    node.height = (fitSize.height > 0) ? MLNUIPointValue(fitSize.height) : MLNUIValueAuto;
    node.maxWidth = (maxSize.width > 0) ? MLNUIPointValue(maxSize.width) : MLNUIValueUndefined;
    node.maxHeight = (maxSize.height > 0) ? MLNUIPointValue(maxSize.height) : MLNUIValueUndefined;
}

#pragma mark - Override

- (BOOL)mlnui_isRootView {
    return YES;
}

- (BOOL)mlnui_allowVirtualLayout {
    return NO;
}

// 当 cell 上含有异步内容 (如：加载网络图片)，当异步内容加载完成后，需要重新调整 cell 大小
- (void)mlnui_layoutDidChange {
    [super mlnui_layoutDidChange];
    if (!CGRectEqualToRect(self.oldFrame, CGRectZero)) {
        if (self.didChangeLayout) {
            self.didChangeLayout(self.mlnuiLayoutFrame.size);
        }
    }
    self.oldFrame = self.mlnuiLayoutFrame;
}

#pragma mark - Override Method For Lua
- (void)luaui_setCornerRadius:(CGFloat)cornerRadius
{
    if (self.cell) {
        [self.cell luaui_setCornerRadius:cornerRadius];
        [self.cell.contentView luaui_setCornerRadius:cornerRadius];
    }
    [super luaui_setCornerRadius:cornerRadius];
}

- (void)setLuaui_marginTop:(CGFloat)luaui_marginTop
{
    MLNUIKitLuaAssert(luaui_marginTop == 0, @"The contentView should not called marginTop");
}

- (void)setLuaui_marginLeft:(CGFloat)luaui_marginLeft
{
    MLNUIKitLuaAssert(luaui_marginLeft == 0, @"The contentView should not called marginLeft");
}

- (void)setLuaui_marginRight:(CGFloat)luaui_marginRight
{
    MLNUIKitLuaAssert(luaui_marginRight == 0, @"The contentView should not called marginRight");
}

- (void)setLuaui_marginBottom:(CGFloat)luaui_marginBottom
{
    MLNUIKitLuaAssert(luaui_marginBottom == 0, @"The contentView should not called marginBottom");
}

@end

@implementation MLNUIReuseAutoSizeContentViewNode

@end

@implementation MLNUIReuseAutoSizeContentView

#pragma mark - Override

- (Class)mlnui_bindedLayoutNodeClass {
    return [MLNUIReuseAutoSizeContentViewNode class];
}

- (CGSize)caculateContentViewSizeWithMaxSize:(CGSize)maxSize applyToView:(BOOL)apply {
    MLNUILayoutNode *node = [self mlnui_layoutNode];
    node.width = MLNUIValueAuto; // 计算自适应宽高，需要确保清除固定宽高设置，否则计算出的是固定宽高
    node.height = MLNUIValueAuto;
    return [super caculateContentViewSizeWithMaxSize:maxSize apply:apply];
}

@end
