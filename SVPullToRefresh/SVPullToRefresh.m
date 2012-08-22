//
// SVPullToRefresh.m
//
// Created by Sam Vermette on 23.04.12.
// Copyright (c) 2012 samvermette.com. All rights reserved.
//
// https://github.com/samvermette/SVPullToRefresh
//

#import <QuartzCore/QuartzCore.h>
#import "SVPullToRefresh.h"

enum {
    SVPullToRefreshStateHidden = 1,
	SVPullToRefreshStateVisible,
    SVPullToRefreshStateTriggered,
    SVPullToRefreshStateLoading
};

typedef NSUInteger SVPullToRefreshState;

static CGFloat const SVPullToRefreshViewHeight = 60;

@interface SVPullToRefreshArrow : UIView
@property (nonatomic, strong) UIColor *arrowColor;
@end


@interface SVPullToRefresh ()
{
    BOOL isAnimating;
}

- (id)initWithScrollView:(UIScrollView*)scrollView;
- (void)rotateArrow:(float)degrees hide:(BOOL)hide;
- (void)setScrollViewContentInset:(UIEdgeInsets)contentInset;
- (void)scrollViewDidScroll:(CGPoint)contentOffset;

- (void)startObservingScrollView;
- (void)stopObservingScrollView;

@property (nonatomic, copy) void (^pullToRefreshActionHandler)(void);
@property (nonatomic, copy) void (^infiniteScrollingActionHandler)(void);
@property (nonatomic, readwrite) SVPullToRefreshState state;

@property (nonatomic, strong) UIImageView *arrowImageView;

@property (nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic, strong) UILabel *titleLabel;

@property (nonatomic, strong) UIView *loadingView;
@property (nonatomic, strong) CAKeyframeAnimation *anim;

@property (nonatomic, strong, readonly) UILabel *dateLabel;

@property (nonatomic, unsafe_unretained) UIScrollView *scrollView;
@property (nonatomic, readwrite) UIEdgeInsets originalScrollViewContentInset;
@property (nonatomic, strong) UIView *originalTableFooterView;

@property (nonatomic, assign) BOOL showsPullToRefresh;
@property (nonatomic, assign) BOOL showsInfiniteScrolling;
@property (nonatomic, assign) BOOL isObservingScrollView;

@end

@implementation SVPullToRefresh

// public properties
@synthesize pullToRefreshActionHandler, infiniteScrollingActionHandler, arrowColor, textColor, activityIndicatorViewStyle, lastUpdatedDate, dateFormatter, layer;

@synthesize state;
@synthesize scrollView = _scrollView;
@synthesize activityIndicatorView, titleLabel, dateLabel, originalScrollViewContentInset, originalTableFooterView, showsPullToRefresh, showsInfiniteScrolling, isObservingScrollView, arrowImageView;

- (void)dealloc {
    [self stopObservingScrollView];
}

- (id)initWithScrollView:(UIScrollView *)scrollView {
    self = [super initWithFrame:CGRectZero];
    self.scrollView = scrollView;
    
    // default styling values
    self.activityIndicatorViewStyle = UIActivityIndicatorViewStyleGray;
    self.textColor = [UIColor darkGrayColor];
    
    self.originalScrollViewContentInset = self.scrollView.contentInset;
    
    return self;
}

- (void)willMoveToSuperview:(UIView *)newSuperview {
    if(newSuperview == self.scrollView)
        [self startObservingScrollView];
    else if(newSuperview == nil)
        [self stopObservingScrollView];
}

- (void)layoutSubviews {
    CGFloat remainingWidth = self.superview.bounds.size.width-180;
    float position = 0.50;
    
    CGRect titleFrame = titleLabel.frame;
    titleFrame.origin.x = ceil(remainingWidth*position+44);
    titleLabel.frame = titleFrame;
    
    CGRect dateFrame = dateLabel.frame;
    dateFrame.origin.x = titleFrame.origin.x;
    dateLabel.frame = dateFrame;
    
    CGRect arrowFrame = arrowImageView.frame;
    arrowFrame.origin.x = ceil(remainingWidth*position);
    arrowImageView.frame = arrowFrame;
    
	
    if(infiniteScrollingActionHandler) {
        self.activityIndicatorView.center = CGPointMake(round(self.bounds.size.width/2), round(self.bounds.size.height/2));
    } else
        self.activityIndicatorView.center = self.arrowImageView.center;
}

#pragma mark - Getters

- (UIImageView *) arrowImageView
{
    if (!arrowImageView && pullToRefreshActionHandler) {
        self.arrowImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 10, 10, 14)];
        arrowImageView.backgroundColor = [UIColor clearColor];
        arrowImageView.image = [UIImage imageNamed:@"icon-arrow.png"];
    }
    return arrowImageView;
}

- (UIActivityIndicatorView *)activityIndicatorView {
    if(!activityIndicatorView) {
        activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        activityIndicatorView.hidesWhenStopped = YES;
        [self addSubview:activityIndicatorView];
    }
    return activityIndicatorView;
}

- (UILabel *)dateLabel {
    if(!dateLabel && pullToRefreshActionHandler) {
        dateLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 28, 180, 20)];
        dateLabel.font = [UIFont systemFontOfSize:12];
        dateLabel.backgroundColor = [UIColor clearColor];
        dateLabel.textColor = textColor;
        [self addSubview:dateLabel];
        
        CGRect titleFrame = titleLabel.frame;
        titleFrame.origin.y = 12;
        titleLabel.frame = titleFrame;
    }
    return dateLabel;
}

- (NSDateFormatter *)dateFormatter {
    if(!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
		[dateFormatter setDateStyle:NSDateFormatterShortStyle];
		[dateFormatter setTimeStyle:NSDateFormatterShortStyle];
		dateFormatter.locale = [NSLocale currentLocale];
    }
    return dateFormatter;
}

- (UIEdgeInsets)originalScrollViewContentInset {
    return UIEdgeInsetsMake(originalScrollViewContentInset.top, self.scrollView.contentInset.left, self.scrollView.contentInset.bottom, self.scrollView.contentInset.right);
}

#pragma mark - Setters

- (void)setPullToRefreshActionHandler:(void (^)(void))actionHandler {
    pullToRefreshActionHandler = [actionHandler copy];
    [_scrollView addSubview:self];
    self.showsPullToRefresh = YES;
    
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, 150, 20)];
    titleLabel.text = NSLocalizedString(@"Pull to refresh...",);
    titleLabel.font = [UIFont boldSystemFontOfSize:14];
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.textColor = textColor;
    [self addSubview:titleLabel];
    
    [self addSubview:self.arrowImageView];
    
    self.state = SVPullToRefreshStateHidden;
    self.frame = CGRectMake(0, -SVPullToRefreshViewHeight-originalScrollViewContentInset.top, self.scrollView.bounds.size.width, SVPullToRefreshViewHeight);
    self.backgroundColor = [UIColor grayColor];
    
    self.loadingView = [[UIView alloc] initWithFrame:CGRectMake(-40, 50, 40, 10)];
    self.loadingView.backgroundColor = [UIColor redColor];
    
    self.anim = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    
    [self addSubview:self.loadingView];
    
}

- (void)setInfiniteScrollingActionHandler:(void (^)(void))actionHandler {
    self.originalTableFooterView = [(UITableView*)self.scrollView tableFooterView];
    infiniteScrollingActionHandler = [actionHandler copy];
    self.showsInfiniteScrolling = YES;
    self.frame = CGRectMake(0, 0, self.scrollView.bounds.size.width, SVPullToRefreshViewHeight);
    [(UITableView*)self.scrollView setTableFooterView:self];
    self.state = SVPullToRefreshStateHidden;
    [self layoutSubviews];
}

- (void)setTextColor:(UIColor *)newTextColor {
    textColor = newTextColor;
    titleLabel.textColor = newTextColor;
	dateLabel.textColor = newTextColor;
}

- (void)setActivityIndicatorViewStyle:(UIActivityIndicatorViewStyle)viewStyle {
    self.activityIndicatorView.activityIndicatorViewStyle = viewStyle;
}

- (void)setScrollViewContentInset:(UIEdgeInsets)contentInset {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.scrollView.contentInset = contentInset;
    } completion:^(BOOL finished) {
        if(self.state == SVPullToRefreshStateHidden && contentInset.top == self.originalScrollViewContentInset.top)
            [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
                arrowImageView.alpha = 0;
            } completion:NULL];
    }];
}

- (void)setLastUpdatedDate:(NSDate *)newLastUpdatedDate {
    self.dateLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Last Updated: %@",), newLastUpdatedDate?[self.dateFormatter stringFromDate:newLastUpdatedDate]:NSLocalizedString(@"Never",)];
}

- (void)setDateFormatter:(NSDateFormatter *)newDateFormatter {
	dateFormatter = newDateFormatter;
    self.dateLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Last Updated: %@",), self.lastUpdatedDate?[newDateFormatter stringFromDate:self.lastUpdatedDate]:NSLocalizedString(@"Never",)];
}

- (void)setShowsInfiniteScrolling:(BOOL)show {
    showsInfiniteScrolling = show;
    if(!show)
        [(UITableView*)self.scrollView setTableFooterView:self.originalTableFooterView];
    else
        [(UITableView*)self.scrollView setTableFooterView:self];
}

#pragma mark -

- (void)startObservingScrollView {
    if (self.isObservingScrollView)
        return;
    
    [self.scrollView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
    [self.scrollView addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
    self.isObservingScrollView = YES;
}

- (void)stopObservingScrollView {
    if(!self.isObservingScrollView)
        return;
    
    [self.scrollView removeObserver:self forKeyPath:@"contentOffset"];
    [self.scrollView removeObserver:self forKeyPath:@"frame"];
    self.isObservingScrollView = NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if([keyPath isEqualToString:@"contentOffset"])
        [self scrollViewDidScroll:[[change valueForKey:NSKeyValueChangeNewKey] CGPointValue]];
    else if([keyPath isEqualToString:@"frame"])
        [self layoutSubviews];
}

- (void)scrollViewDidScroll:(CGPoint)contentOffset {
    //NSLog(@"%@", NSStringFromCGRect(self.arrow.frame));
    if(pullToRefreshActionHandler) {
        if (self.state == SVPullToRefreshStateLoading) {
            CGFloat offset = MAX(self.scrollView.contentOffset.y * -1, 0);
            offset = MIN(offset, self.originalScrollViewContentInset.top + SVPullToRefreshViewHeight);
            self.scrollView.contentInset = UIEdgeInsetsMake(self.originalScrollViewContentInset.top + 10, 0.0f, 0.0f, 0.0f);
        } else {
            CGFloat scrollOffsetThreshold = self.frame.origin.y;//-self.originalScrollViewContentInset.top;
            
            if(!self.scrollView.isDragging && self.state == SVPullToRefreshStateTriggered){
                self.state = SVPullToRefreshStateLoading;
                NSLog(@"set to loading");
            }
            else if(contentOffset.y > scrollOffsetThreshold && contentOffset.y < -self.originalScrollViewContentInset.top && self.scrollView.isDragging && self.state != SVPullToRefreshStateLoading)
            {
                self.state = SVPullToRefreshStateVisible;
                NSLog(@"set to visible");
            }
            else if(contentOffset.y < scrollOffsetThreshold && self.scrollView.isDragging && self.state == SVPullToRefreshStateVisible && !isAnimating)
            {
                self.state = SVPullToRefreshStateTriggered;
                NSLog(@"set to triggered");
            }
            else if(contentOffset.y >= -self.originalScrollViewContentInset.top && self.state != SVPullToRefreshStateHidden)
            {
                self.state = SVPullToRefreshStateHidden;
                NSLog(@"set to hidden");
            }
        }
    }
    else if(infiniteScrollingActionHandler) {
        CGFloat scrollOffsetThreshold = self.scrollView.contentSize.height-self.scrollView.bounds.size.height-self.originalScrollViewContentInset.top;
        
        if(contentOffset.y > MAX(scrollOffsetThreshold, self.scrollView.bounds.size.height-self.scrollView.contentSize.height) && self.state == SVPullToRefreshStateHidden)
            self.state = SVPullToRefreshStateLoading;
        else if(contentOffset.y < scrollOffsetThreshold)
            self.state = SVPullToRefreshStateHidden;
    }
}

- (void)triggerRefresh {
    self.state = SVPullToRefreshStateLoading;
    [self.scrollView setContentOffset:CGPointMake(0, -SVPullToRefreshViewHeight-originalScrollViewContentInset.top) animated:YES];
}

- (void)startAnimating{
    state = SVPullToRefreshStateLoading;
    titleLabel.text = NSLocalizedString(@"Loading...",);
    [self.activityIndicatorView startAnimating];
    UIEdgeInsets newInsets = self.originalScrollViewContentInset;
    newInsets.top = self.frame.origin.y*-1+self.originalScrollViewContentInset.top;
    newInsets.bottom = self.scrollView.contentInset.bottom;
    [self setScrollViewContentInset:newInsets];
    CGPoint originalPoint = CGPointMake(0, -self.frame.size.height-originalScrollViewContentInset.top);
    [self.scrollView setContentOffset:originalPoint animated:NO];
    [self rotateArrow:0 hide:YES];
    
    [self performSelector:@selector(startAnimation) withObject:nil afterDelay:0.7];
    //[self startAnimation];
}

- (void)startAnimation
{
    CGPoint testPoint = CGPointMake(0, -10-originalScrollViewContentInset.top);
    [self.scrollView setContentOffset:testPoint animated:YES];
    if (!isAnimating) {
        //CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        self.anim.delegate = self;
        //self.anim.removedOnCompletion = YES;
        
        NSArray *times = [NSArray arrayWithObjects:
                          [NSNumber numberWithFloat:0.0],
                          //[NSNumber numberWithFloat:0.33],
                          [NSNumber numberWithFloat:0.5],
                          [NSNumber numberWithFloat:1.0],
                          nil];
        
        [self.anim setKeyTimes:times];
	    
        NSArray *values = [NSArray arrayWithObjects:
                           [NSValue valueWithCGPoint:CGPointMake(0, 55)],
                           [NSValue valueWithCGPoint:CGPointMake(320, 55)],
                           [NSValue valueWithCGPoint:CGPointMake(0, 55)],
                           nil];
        
        [self.anim setValues:values];
        [self.anim setDuration:2.0]; //seconds
        //[anim setCalculationMode:kCAAnimationRotateAutoReverse];
        [self.loadingView.layer addAnimation:self.anim forKey:@"position"];
        isAnimating = YES;
    }
}

- (void) animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    //NSLog(@"state: %i isAnimating: %i", self.state, isAnimating);
    if (self.state == SVPullToRefreshStateLoading){
        isAnimating = NO;
        [self startAnimation];
    }
    else
        isAnimating = NO;
}

- (void)stopAnimating {
    self.state = SVPullToRefreshStateHidden;
}

- (void)setState:(SVPullToRefreshState)newState {
    
    if(pullToRefreshActionHandler && !self.showsPullToRefresh && !self.activityIndicatorView.isAnimating) {
        titleLabel.text = NSLocalizedString(@"",);
        [self.activityIndicatorView stopAnimating];
        [self setScrollViewContentInset:self.originalScrollViewContentInset];
        [self rotateArrow:0 hide:YES];
        return;
    }
    
    if(infiniteScrollingActionHandler && !self.showsInfiniteScrolling)
        return;
    
    if(state == newState)
        return;
    
    state = newState;
    
    if(pullToRefreshActionHandler) {
        switch (newState) {
            case SVPullToRefreshStateHidden:
                titleLabel.text = NSLocalizedString(@"Pull to refresh...",);
                [self.activityIndicatorView stopAnimating];
                [self setScrollViewContentInset:self.originalScrollViewContentInset];
                [self rotateArrow:0 hide:NO];
                [self.loadingView.layer removeAnimationForKey:@"position"];
                break;
                
            case SVPullToRefreshStateVisible:
                titleLabel.text = NSLocalizedString(@"Pull to refresh...",);
                arrowImageView.alpha = 1;
                [self.activityIndicatorView stopAnimating];
                [self setScrollViewContentInset:self.originalScrollViewContentInset];
                [self rotateArrow:0 hide:NO];
                break;
                
            case SVPullToRefreshStateTriggered:
                titleLabel.text = NSLocalizedString(@"Release to refresh...",);
                [self rotateArrow:M_PI hide:NO];
                break;
                
            case SVPullToRefreshStateLoading:
                [self startAnimating];
                pullToRefreshActionHandler();
                break;
        }
    }
    else if(infiniteScrollingActionHandler) {
        switch (newState) {
            case SVPullToRefreshStateHidden:
                [self.activityIndicatorView stopAnimating];
                break;
                
            case SVPullToRefreshStateLoading:
                [self.activityIndicatorView startAnimating];
                infiniteScrollingActionHandler();
                break;
        }
    }
}

- (void)rotateArrow:(float)degrees hide:(BOOL)hide {
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.arrowImageView.layer.transform = CATransform3DMakeRotation(degrees, 0, 0, 1);
        self.arrowImageView.layer.opacity = !hide;
        //[self.arrow setNeedsDisplay];//ios 4
    } completion:NULL];
}

@end


#pragma mark - UIScrollView (SVPullToRefresh)
#import <objc/runtime.h>

static char UIScrollViewPullToRefreshView;
static char UIScrollViewInfiniteScrollingView;

@implementation UIScrollView (SVPullToRefresh)

@dynamic pullToRefreshView, showsPullToRefresh, infiniteScrollingView, showsInfiniteScrolling;

- (void)addPullToRefreshWithActionHandler:(void (^)(void))actionHandler {
    self.pullToRefreshView.pullToRefreshActionHandler = actionHandler;
}

- (void)addInfiniteScrollingWithActionHandler:(void (^)(void))actionHandler {
    self.infiniteScrollingView.infiniteScrollingActionHandler = actionHandler;
}

- (void)setPullToRefreshView:(SVPullToRefresh *)pullToRefreshView {
    [self willChangeValueForKey:@"pullToRefreshView"];
    objc_setAssociatedObject(self, &UIScrollViewPullToRefreshView,
                             pullToRefreshView,
                             OBJC_ASSOCIATION_RETAIN);
    [self didChangeValueForKey:@"pullToRefreshView"];
}

- (void)setInfiniteScrollingView:(SVPullToRefresh *)pullToRefreshView {
    [self willChangeValueForKey:@"infiniteScrollingView"];
    objc_setAssociatedObject(self, &UIScrollViewInfiniteScrollingView,
                             pullToRefreshView,
                             OBJC_ASSOCIATION_RETAIN);
    [self didChangeValueForKey:@"infiniteScrollingView"];
}

- (SVPullToRefresh *)pullToRefreshView {
    SVPullToRefresh *pullToRefreshView = objc_getAssociatedObject(self, &UIScrollViewPullToRefreshView);
    if(!pullToRefreshView) {
        pullToRefreshView = [[SVPullToRefresh alloc] initWithScrollView:self];
        self.pullToRefreshView = pullToRefreshView;
    }
    return pullToRefreshView;
}

- (void)setShowsPullToRefresh:(BOOL)showsPullToRefresh {
    self.pullToRefreshView.showsPullToRefresh = showsPullToRefresh;
}

- (BOOL)showsPullToRefresh {
    return self.pullToRefreshView.showsPullToRefresh;
}

- (SVPullToRefresh *)infiniteScrollingView {
    SVPullToRefresh *infiniteScrollingView = objc_getAssociatedObject(self, &UIScrollViewInfiniteScrollingView);
    if(!infiniteScrollingView) {
        infiniteScrollingView = [[SVPullToRefresh alloc] initWithScrollView:self];
        self.infiniteScrollingView = infiniteScrollingView;
    }
    return infiniteScrollingView;
}

- (void)setShowsInfiniteScrolling:(BOOL)showsInfiniteScrolling {
    self.infiniteScrollingView.showsInfiniteScrolling = showsInfiniteScrolling;
}

- (BOOL)showsInfiniteScrolling {
    return self.infiniteScrollingView.showsInfiniteScrolling;
}

@end