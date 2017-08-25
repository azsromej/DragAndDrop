//
//  DragAndDrop.m
//  StructuredPlan
//
//  Created by Steven Romej on 5/20/15.
//  Copyright (c) 2015 Steven Romej. All rights reserved.
//

#import "DragAndDrop.h"
#import "Logging.h"

@class DraggingAnimationDefaultContext;
@class SessionDraggingInfo;

// =======================================================
// Dragging Session
// =======================================================

@interface DraggingSession ()
@property (nonatomic, strong) SessionDraggingInfo *sessionDraggingInfo;
// Modeling this after NSDraggingSession, which exposes the pasteboard of the NSDraggingItem
// FIXME: probably don't need this.
/*
 OSX docs on NSDraggingItem:
When the developer creates an NSDraggingItem instance , it is for use with the view method beginDraggingSessionWithItems:event:source: 
 During the invocation of that method, the pasteboardWriter is placed onto the dragging pasteboard for the NSDraggingSession that 
 contains the dragging item instance.
 */
//@property (nonatomic, strong) NSDictionary *draggedItemInfo;
@end

@implementation DraggingSession

//- (NSDictionary *)draggedItemInfo {
//    return self.sessionDraggingInfo.item.draggedItemInfo;
//}

@end



// =======================================================
// Dragging Item
// =======================================================

@interface DraggingItem ()
/// The actual dragged object to be used by destination
@property (nonatomic, strong) NSDictionary *draggedItemInfo;
@end

@implementation DraggingItem

- (instancetype)init {
    return [self initWithDraggedItemInfo:nil];
}

- (instancetype)initWithDraggedItemInfo:(NSDictionary *)info {
    self = [super init];
    if (self) {
        _draggedItemInfo = info;
    }
    return self;
}

@end

// =======================================================
// SessionDraggingInfo
// =======================================================
@interface SessionDraggingInfo : NSObject <DraggingInfo>
@property (nonatomic, weak) DraggingSession *session;
@property (nonatomic, strong) DraggingItem *item;
// For <DraggingInfo>
/// The dragging source is set in call to startDraggingSessionWithItem:
@property (nonatomic, weak) id<DraggingSource> source;
@property (nonatomic, assign) DragOperation sourceOperationMask;
@property (nonatomic, assign) CGPoint snapshotCenterInDestination;
@end

@implementation SessionDraggingInfo

+ (SessionDraggingInfo *)draggingInfoForSession:(DraggingSession *)session item:(DraggingItem *)item {
    SessionDraggingInfo *info = [[SessionDraggingInfo alloc] init];
    info.session = session;
    info.item = item;
    return info;
}

#pragma mark - <DraggingInfo>

- (UIView *)snapshotView {
    return self.item.snapshotView;
}

- (DragOperation)sourceOperationMask {
    if ([self.source respondsToSelector:@selector(sourceOperationMaskForDraggingSession:)]) {
        return [self.source sourceOperationMaskForDraggingSession:self.session];
    }
    
    return DragOperationNone;
}

- (NSDictionary *)draggedItemInfo {
    return self.item.draggedItemInfo;
}

@end


// =======================================================
// Dragging Destination Info
// =======================================================

@interface DraggingDestinationInfo : NSObject
@property (nonatomic, strong) id<DraggingDestination> draggingDestination;
@property (nonatomic, strong) UIView *destinationView;
@property (nonatomic, assign) BOOL dragIsInside;
/// This tracks the operation the  destination returns during draggingEntered/Updated
@property (nonatomic, assign) DragOperation dragOperation;
/// If the dragging destination conforms to the autoscroll protocol, this gets updated to reflect current status.
/// It remains set to direction .None if the destination doesn't support the autoscroll protocol.
@property (nonatomic, assign) AutoscrollDirection autoscrollDirection;
@property (nonatomic, assign) CGFloat autoscrollVerticalIncrement;
@property (nonatomic, assign) CGFloat autoscrollHorizontalIncrement;
@end

@implementation DraggingDestinationInfo

@end

// =======================================================
// Dragging Manager
// =======================================================

@interface DraggingManager () <UIGestureRecognizerDelegate>

@property (nonatomic, weak) UIView *draggingContainerView;
@property (nonatomic, strong) UIPanGestureRecognizer *draggingPanRecognizer;
@property (nonatomic, weak) UILongPressGestureRecognizer *initiatingLongPressRecognizer;
// Autoscroll support
@property (nonatomic, strong) CADisplayLink *displayLink;

@property (nonatomic, strong) DraggingSession *draggingSession;
@property (nonatomic, strong) id<DraggingSource> draggingSource;
@property (nonatomic, strong) NSMutableSet *draggingDestinations;

@property (nonatomic, assign) BOOL isEndingSession;

- (void)completeCustomDraggingAnimationDestination:(id<DraggingDestination>)destination operation:(DragOperation)operation;

@end


// ------- this had to come after defining completeDraggingSession
// TODO: this feels unnecessary and overly complex. If an animationDelegate is set, it could just be its responsibiltiy
// to call completeDraggingAnimation (which would be defined on the DraggingManager)
// This could just be an object. I'm doing all this protocol context stuff similar to UIViewControllerContextTransitioning
@interface DraggingAnimationDefaultContext : NSObject <DraggingAnimationContext>
@property (nonatomic, weak) DraggingManager *draggingManager;
// if this is set, it means a destination accepted the drop
@property (nonatomic, weak) id<DraggingDestination> destination;
// The operation that the destination is going to perform
@property (nonatomic, assign) DragOperation dragOperation;
@end

@implementation DraggingAnimationDefaultContext

+ (DraggingAnimationDefaultContext *)contextWithManager:(DraggingManager *)manager draggingDestination:(id<DraggingDestination>)destination operation:(DragOperation)operation {
    DraggingAnimationDefaultContext *context = [[DraggingAnimationDefaultContext alloc] init];
    context.draggingManager = manager;
    context.destination = destination;
    context.dragOperation = operation;
    return context;
}

- (UIView *)snapshotView {
    return [self.draggingManager.draggingSession.sessionDraggingInfo snapshotView];
}

- (id<DraggingDestination>)draggingDestination {
    return self.destination;
}

// TODO: evaluate need for this method; does a custom animation need the source?
- (id<DraggingSource>)draggingSource {
    return self.draggingManager.draggingSource;
}

- (void)completeDraggingAnimation {
    [self.draggingManager completeCustomDraggingAnimationDestination:self.destination operation:self.dragOperation];
}

@end

@implementation DraggingManager

#pragma mark - Autoscroll

// For debugging
- (NSString *)stringForAutoscrollDirectionOptions:(AutoscrollDirection)options {
    NSMutableString *buf = [NSMutableString string];
    if (options == AutoscrollDirectionNone)
        [buf appendString:@".None"];
    
    if (options & AutoscrollDirectionUp)
        [buf appendString:@".Up "];
    if (options & AutoscrollDirectionDown)
        [buf appendString:@".Down "];
    if (options & AutoscrollDirectionLeft)
        [buf appendString:@".Left "];
    if (options & AutoscrollDirectionRight)
        [buf appendString:@".Right "];

    return buf;
}

- (void)startAutoscrollTimer {
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleDisplayLinkTimerFired:)];
    //_displayLink.frameInterval = 3; // slows the updates for debugging
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)stopAutoscrollTimer {
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    //self.autoscrollDirection = AutoscrollDirectionNone;
}

/// Considering a way to use the delta times between this firing (or interval),
/// but for now I'm assuming 60 fps and setting my autoscroll distance to be 5pts

/**
 How to calculate the minimum and maximum y offsets for the scroll view bounds
 (ie, the contentOffset).
 
 In the case of no contentInset, scrolling stops/bounces at the content bounds.
 
 a) Less than a screen of content:
    excess: (content - viewable) < 0
    min-y: 0
    max-y: everything is visible, use min-y
 
 b) More than a screen of content:
    excess: (content - viewable) >= 0
    min-y: 0
    max-y: excess (ie, if you stick out 5pt, let user scroll down 5pt to reveal)
 
 
 If insets are present, they abut the content and allow additional scrolling. This
 is the general case; if there are no insets top and bottom are 0.
 
 a) Less than a screen of total content:
    excess: top + (content - viewable) + bottom < 0
    min-y: 0 - top (ie, -64 in most iOS apps)
    max-y: everything visible, use min-y
 
 b) More than a screen of total content:
    excess: top + (content - viewable) + bottom >= 0
    min-y: 0 - top
    max-y: min-y + excess (ie, start from min and move down excess pts)
 
 TL;DR
 miny: -top
 maxy: miny + fmax(0, excess)
 

 ┌┬────────────────┬┐  ┌┬────────────────┬┐  ┌ ─ ─ ─ ─ ─
 ││      top       ││  ││      top       ││             │
 ││                ││  ││                ││  │
 │└───┬────────┬───┘│  │└───┬────────┬───┘│             │
 │    │xxxxxxxx│    │  │    │xxxxxxxx│    │  │
 │    │xxxxxxxx│    │  │    │xxxxxxxx│    │             │
 │    │xxxxxxxx│    │  │    │xxxxxxxx│    │  │
 │    │xxxxxxxx│    │  │    │xxxxxxxx│    │    viewport │
 │    │xxxxxxxx│    │  │    │xxxxxxxx│    │  │
 │    │xxxxxxxx│    │  │    │xxxxxxxx│    │             │
 │    │xxxxxxxx│    │  │    │xxxxxxxx│    │  │
 │    │xxxxxxxx│    │  │┌───┴────────┴───┐│             │
 │    │xxxxxxxx│    │  ││     bottom     ││  │
 │    │xxxxxxxx│    │  │└────────────────┘│             │
 │    │xxxxxxxx│    │  │      -excess     │  │
 └────┤xxxxxxxx├────┘  └──────────────────┘   ─ ─ ─ ─ ─ ┘
  ┌───┴────────┴───┐
  │     bottom     │    excess
  └────────────────┘
 
 */
- (void)handleDisplayLinkTimerFired:(CADisplayLink *)timer {
    for (DraggingDestinationInfo *info in self.draggingDestinations) {
        
        //SRLog(@"info.autoscrollDirection: %@", [self stringForAutoscrollDirectionOptions:info.autoscrollDirection]);
        
        // Most common case is that dragged view isn't at screen edges, so check for .None first.
        // Also skip if the operation is Delete (no need to scroll to a "better" place to drop when doing delete)
        if (info.autoscrollDirection == AutoscrollDirectionNone || info.dragOperation == DragOperationDelete) {
            // Skip. The <DraggingAutoscroll> object won't be notified as there's nothing to do
            continue;
        }

        id<DraggingAutoscroll> autoscrollable = (id<DraggingAutoscroll>)info.draggingDestination;
        UIScrollView *scrollView = [autoscrollable autoscrollView];
        
        CGSize frameSize = scrollView.bounds.size;
        CGSize contentSize = scrollView.contentSize;
        CGPoint contentOffset = scrollView.contentOffset;
        // The autoscroll increment amount
        CGFloat ydistance = info.autoscrollVerticalIncrement;
        CGFloat xdistance = info.autoscrollHorizontalIncrement;
    
        // The key thing to keep in mind is that normally scrolling stops at the boundaries of the content.
        // If contentInsets are set, they permit the scroll view bounds to move beyond the content.
        // If there is less than a screen of content, the max offset is (0-top), even if a bottom inset exists
        
        CGPoint adjustedBoundsOrigin = CGPointZero;
        
        // Up-Down adjustments
        if (info.autoscrollDirection & AutoscrollDirectionUp) {
            //SRLog(@"applying .Up");
            CGFloat miny = -scrollView.contentInset.top;
            CGFloat newy = contentOffset.y - ydistance;
            // Don't scroll up beyond min-y
            adjustedBoundsOrigin.y = fmax(miny, newy);
            
        } else if (info.autoscrollDirection & AutoscrollDirectionDown) {
            //SRLog(@"applying .Down");
            CGFloat miny = -scrollView.contentInset.top;
            CGFloat excess = scrollView.contentInset.top + (contentSize.height - frameSize.height) + scrollView.contentInset.bottom;
            CGFloat maxy = miny + fmax(0, excess); // ie, if excess >= 0 move offset by excess to accomodate
//            if (excess >= 0) {
//                maxy += excess;
//            }
            CGFloat newy = contentOffset.y + ydistance;
            // Don't scroll past max-y
            adjustedBoundsOrigin.y = fmin(maxy, newy);
        }
        
        // Left-Right adjustments
        if (info.autoscrollDirection & AutoscrollDirectionLeft) {
            SRLog(@"applying .Left");
            CGFloat minx = -scrollView.contentInset.left;
            CGFloat newx = contentOffset.x - xdistance;
            adjustedBoundsOrigin.x = fmax(minx, newx);
            
        } else if (info.autoscrollDirection & AutoscrollDirectionRight) {
            SRLog(@"applying .Right");
            CGFloat minx = -scrollView.contentInset.left;
            CGFloat excess = scrollView.contentInset.left + (contentSize.width - frameSize.width) + scrollView.contentInset.right;
            CGFloat maxx = minx + fmax(0, excess);
            CGFloat newx = contentOffset.x + xdistance;
            adjustedBoundsOrigin.x = fmin(maxx, newx);
        }
        
        UIView *snapshot = self.draggingSession.sessionDraggingInfo.item.snapshotView;
        //SRLog(@"contentOffset: %@, loc: %@", NSStringFromCGPoint(scrollView.contentOffset), NSStringFromCGPoint([snapshot.superview convertPoint:snapshot.center fromView:scrollView]));
        scrollView.contentOffset = adjustedBoundsOrigin;
        //SRLog(@"contentOffset: %@, loc: %@", NSStringFromCGPoint(scrollView.contentOffset), NSStringFromCGPoint([snapshot.superview convertPoint:snapshot.center fromView:scrollView]));
        
        CGPoint location = [snapshot.superview convertPoint:snapshot.center toView:scrollView];
        //SRLog(@"after contentOffset adjustment, snapshot center is %@", NSStringFromCGPoint(location));
        
        //SRLog(@"autoscroll updated in direction: %@", [self stringForAutoscrollDirectionOptions:info.autoscrollDirection]);
        timer.paused = YES; // Defend against frame loss by pausing the timer while animating the row swap; see Neuberg's book
        [autoscrollable autoscrollUpdatedInDirection:info.autoscrollDirection location:location];
        timer.paused = NO;
    }
}

- (AutoscrollDirection)autoscrollDirectionForAutoscrollable:(id<DraggingAutoscroll>)autoscrollable {
    UIEdgeInsets autoscrollInsets = [autoscrollable autoscrollRegionInsets];
    UIScrollView *scrollView = [autoscrollable autoscrollView];
    
    // Get the location of the dragged view in terms of the autoscroll view
    UIView *snapshot = [self.draggingSession.sessionDraggingInfo snapshotView];
    CGPoint location = [snapshot.superview convertPoint:snapshot.center toView:scrollView];
    
#warning TODO - re-evaluate because pushing dragged center below screen causes autoscroll to stop which may not be desired
    if (!CGRectContainsPoint(scrollView.bounds, location)) {
        SRLog(@"the scrollView bounds %@ doesn't include the snapshot point %@, so no autoscroll", NSStringFromCGRect(scrollView.bounds), NSStringFromCGPoint(location));
        return AutoscrollDirectionNone;
    }
    
//    SRLog(@"location.y %f, scrollView.bounds %@", location.y, NSStringFromCGRect(scrollView.bounds));
    
    // Determine autoscroll status/direction; the CADisplayLink action will use it.
    // Start with direction .None as autoscroll only occurs if location is near periphery.
    AutoscrollDirection directionOptions = AutoscrollDirectionNone;
    
    // Adjust vertical scroll direction if needed
    if (location.y < (CGRectGetMinY(scrollView.bounds) + scrollView.contentInset.top + autoscrollInsets.top)) {
        directionOptions |= AutoscrollDirectionUp;
    } else if (location.y > (CGRectGetMaxY(scrollView.bounds) - autoscrollInsets.bottom)) {
        directionOptions |= AutoscrollDirectionDown;
    }

    // Adjust horizontal scroll direction if needed
    if (location.x < (CGRectGetMinX(scrollView.bounds) + scrollView.contentInset.left + autoscrollInsets.left)) {
        directionOptions |= AutoscrollDirectionLeft;
    } else if (location.x > (CGRectGetMaxX(scrollView.bounds) - autoscrollInsets.right)) {
        directionOptions |= AutoscrollDirectionRight;
    }

    return directionOptions;
}

#pragma mark - Drag and Drop

- (void)manageDraggingInView:(UIView *)view {
    NSAssert(view, @"must provide a view to manage dragging within");
    self.draggingContainerView = view;
    self.draggingPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDraggingPan:)];
    _draggingPanRecognizer.delegate = self;
    [_draggingContainerView addGestureRecognizer:_draggingPanRecognizer];
}

- (void)registerDraggingDestination:(id<DraggingDestination>)destination forView:(UIView *)view {
    DraggingDestinationInfo *destinationInfo = [[DraggingDestinationInfo alloc] init];
    destinationInfo.draggingDestination = destination;
    destinationInfo.destinationView = view;
    destinationInfo.dragIsInside = NO;
    destinationInfo.dragOperation = DragOperationNone;
    destinationInfo.autoscrollDirection = AutoscrollDirectionNone;
    destinationInfo.autoscrollVerticalIncrement = 3.0;
    destinationInfo.autoscrollHorizontalIncrement = 5.0;
    
    if (_draggingDestinations == nil) {
        self.draggingDestinations = [NSMutableSet set];
    }
    [self.draggingDestinations addObject:destinationInfo];
}

- (DraggingSession *)startDraggingSessionWithItem:(DraggingItem *)item initialLongPressRecognizer:(UILongPressGestureRecognizer *)recognizer source:(id<DraggingSource>)source {
    NSAssert(_draggingContainerView, @"can't start a dragging session before setting a view to manage dragging within");
    NSAssert(item.draggedItemInfo != nil, @"You should have called the designated initializer with a dictionary of info about the object being dragged");
    // Only support moving one thing around at a time
    if (_draggingSession) {
        // Don't think it makes sense to return the current session
        return nil;
    }
    
    SRLog(@"starting a dragging session");
    self.draggingSession = [[DraggingSession alloc] init];
    SessionDraggingInfo *draggingInfo = [SessionDraggingInfo draggingInfoForSession:self.draggingSession item:item];
    draggingInfo.source = source;
    self.draggingSession.sessionDraggingInfo = draggingInfo;
    //self.draggingSession.draggedItemInfo = item.draggedItemInfo;
    
    self.draggingSource = source;
    self.initiatingLongPressRecognizer = recognizer;
    // If the user long presses, never pans, then lifts, the session should end. The manager needs to know the long press state.
    // When the session ends, this target-action pair is removed
    [self.initiatingLongPressRecognizer addTarget:self action:@selector(handleInitiatingLongPress:)];

    // This is a cool way to determine the view that was pressed and allows for automatically setting the position of the
    // snapshot so that calling code doesn't have to use calls to convertPoint:toView. The issue is that if the pressed view
    // (eg a cell) has subviews (labels), those labels may be the view returned from hitTest:withEvent. You don't want to base
    // the snapshot's position on those. Best to let calling code determine the appropriate initial position.
//    CGPoint pressPoint = [recognizer locationInView:recognizer.view];
//    UIView *pressView = [recognizer.view hitTest:pressPoint withEvent:nil];
//    if (pressView) {
//        item.snapshotView.center = [pressView.superview convertPoint:pressView.center toView:self.draggingContainerView];
//    }
    
    // Add the dragging view to the container view
    [self.draggingContainerView addSubview:item.snapshotView];
    [self.draggingContainerView bringSubviewToFront:item.snapshotView];
    
    // Intent is to allow this function to return a dragging session and then perform any animation.
    // I'm not sure I fully follow run loops but in my tests dispatch_async is working as I expect for this.
    // See this for more detail on NSRunLoop: http://stackoverflow.com/questions/26178602/order-of-operations-in-runloop-on-ios
    // Initially I had no dispatch_async: the source calls this method to start a session, then gets immediately called back to perform
    // an animation before this method returns. The Cocoa beginDragginSession mentions returning and then starting the actual session
    // on the next iteration of the run loop.
    dispatch_async(dispatch_get_main_queue(), ^{
        DraggingAnimationDefaultContext *context = [DraggingAnimationDefaultContext contextWithManager:self draggingDestination:nil operation:DragOperationNone];
        if ([source respondsToSelector:@selector(animateDraggingLift:)]) {
            id<DraggingAnimation> animator = (id<DraggingAnimation>)source;
            [animator animateDraggingLift:context];
            
        } else {
            [self animateDefaultDraggingLift:context];
        }
    });
    
    return _draggingSession;
}

// the context calls this
- (void)completeCustomDraggingAnimationDestination:(id<DraggingDestination>)destination operation:(DragOperation)operation {
    // Determine whether a drop or lift occurred
    if (self.isEndingSession) {
        // Drop animation, need to do cleanup
        if (destination) {
            [destination completeDragOperation:self.draggingSession.sessionDraggingInfo];
        }
        [self completeDraggingSessionWithOperation:operation];
        
    } else {
        // Lift animation, nothing to do
    }
}

- (void)completeDraggingSessionWithOperation:(DragOperation)operation {
    // Called early while the session still exists
    [self.draggingSource draggingSessionEnded:self.draggingSession operation:operation];

    [[self.draggingSession.sessionDraggingInfo snapshotView] removeFromSuperview];
    [self.initiatingLongPressRecognizer removeTarget:self action:NULL];
    self.initiatingLongPressRecognizer = nil;
    self.draggingSession = nil;
    
    // Reset values that may have changed during session
    for (DraggingDestinationInfo *info in self.draggingDestinations) {
        info.dragIsInside = NO;
    }
    
    self.isEndingSession = NO;
}

// I could call completeCustomDraggingAnimationDestination:operation and get the snapshot via the draggingItem
// but I'm implementing the default like a client would implement its custom animation
- (void)animateDefaultDraggingDrop:(id<DraggingAnimationContext>)context {
    UIView *snapshot = [context snapshotView];
    
    [UIView animateWithDuration:0.25 animations:^{
        snapshot.alpha = 0.1;
        //self.draggingSession.draggingItem.snapshotView.alpha = 0.1;
    } completion:^(BOOL finished) {
        [context completeDraggingAnimation];
        //[destination completeDragOperation:self.draggingSession.draggingItem];
        //[self completeDraggingSessionWithOperation:[context dragOperation]];
    }];
}

/*
 Clues: making sure the default drop and a (delayed) custom drop work the same way, pass messages to destination
 */

- (void)animateDefaultDraggingLift:(id<DraggingAnimationContext>)context {
    // None
}

/// This is called when the dragging session ends (ie, when panning or long pressing ends/cancels).
/// The drop can be animated, so the delegate (DraggingSource) doesn't receive draggingSessionEnded: until
/// after the animation completes.
/// The animation context is used to pass the drag operation around.
- (void)endDraggingSession {
    // Could enter multiple times (via pan end/cancel and long press end/cancel)
    if (self.isEndingSession)
        return;
    
    SRLog(@"ending the dragging session...");
    // Due to animation, it may take a while to fully end the session
    self.isEndingSession = YES;
    
    BOOL dropDestinationAccepted = NO;
    // It's assumed that only one DraggingDestination will be the recipient (if any at all).
    for (DraggingDestinationInfo *info in self.draggingDestinations) {
        if (info.dragIsInside && info.dragOperation != DragOperationNone) {
            dropDestinationAccepted = [info.draggingDestination prepareForDragOperation:self.draggingSession.sessionDraggingInfo];
            if (dropDestinationAccepted) {
                DraggingAnimationDefaultContext *context = [DraggingAnimationDefaultContext contextWithManager:self draggingDestination:info.draggingDestination operation:info.dragOperation];
                
                if ([info.draggingDestination respondsToSelector:@selector(animateDraggingDrop:)]) {
                    id<DraggingAnimation> animator = (id<DraggingAnimation>)info.draggingDestination;
                    [animator animateDraggingDrop:context];
                    
                } else {
                    [self animateDefaultDraggingDrop:context];
                }
            }
        }
    }
    
    if (dropDestinationAccepted)
        return;
    
    // Item wasn't accepted at destination; animate back to the source
    DraggingAnimationDefaultContext *context = [DraggingAnimationDefaultContext contextWithManager:self draggingDestination:nil operation:DragOperationNone];
    
    if ([self.draggingSource respondsToSelector:@selector(animateDraggingDrop:)]) {
        id<DraggingAnimation> animator = (id<DraggingAnimation>)self.draggingSource;
        [animator animateDraggingDrop:context];
        
    } else {
        [self animateDefaultDraggingDrop:context];
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (NSString *)stringForState:(UIGestureRecognizerState)state {
    switch (state) {
        case UIGestureRecognizerStateBegan:
            return @"UIGestureRecognizerStateBegan";
                break;
        case UIGestureRecognizerStateCancelled:
            return @"UIGestureRecognizerStateCancelled";
            break;
        case UIGestureRecognizerStateChanged:
            return @"UIGestureRecognizerStateChanged";
            break;
        case UIGestureRecognizerStateEnded:
            return @"UIGestureRecognizerStateEnded / Recognized";
            break;
        case UIGestureRecognizerStateFailed:
            return @"UIGestureRecognizerStateFailed";
            break;
        case UIGestureRecognizerStatePossible:
            return @"UIGestureRecognizerStatePossible";
            break;
        default:
            break;
    }
    
    return @"FUCKYOU";
}


- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (self.draggingSession == nil) {
        SRLog(@"draggingSession is nil, returning NO for %@", gestureRecognizer);
        return NO;
    }
    
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // Prior to the long press being recognized, this method is called. Since a session hasn't been started yet, the initiatingLongPressRecognizer is nil.
    // If I return NO, this never gets called again.
    // If instead I return yes when the other recognizer is a a UILongPressGestureRecognizer, subsequent calls will come through and the check against
    // initiatingLongPressRecognizer will succeed.
    // A possible fix would be to remove the recognizer param from startDraggingSession and require a call (ie registerSourceWithLongPress:). Actually,
    // that could be an issue because multiple controller's could register as drag sources and each has their own long press.
    if (otherGestureRecognizer == self.initiatingLongPressRecognizer) {
        return YES;
        
    } else if ([otherGestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        SRLog(@"%@ - %@ -> YES", NSStringFromClass([gestureRecognizer class]), NSStringFromClass([otherGestureRecognizer class]));
        return YES;
    }
    
    return NO;
}

#pragma mark - Gestures

- (void)initiatingLongPressEnded:(UILongPressGestureRecognizer *)recognizer {
    SRLog(@"initiating long press ended");
    [self endDraggingSession];
}

- (void)handleInitiatingLongPress:(UILongPressGestureRecognizer *)recognizer {
    switch (recognizer.state) {
        case UIGestureRecognizerStateCancelled:
            [self initiatingLongPressEnded:recognizer];
            break;
        case UIGestureRecognizerStateEnded:
            [self initiatingLongPressEnded:recognizer];
            break;
        default:
            break;
    }
}

/// Adapted From Sadun's BaseGeometry.m
//CGRect RectAroundCenter(CGPoint center, CGSize size) {
//    CGFloat halfWidth = size.width / 2.0f;
//    CGFloat halfHeight = size.height / 2.0f;
//    
//    return CGRectMake(center.x - halfWidth, center.y - halfHeight, size.width, size.height);
//}

// TODO: Currently you can put a finger down elsewhere on the screen and start panning a piece that was lifted by another finger elsewhere; may want to make sure
- (void)handleDraggingPan:(UIPanGestureRecognizer *)recognizer {
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan: {
            SRLog(@"dragging began");
            // Set custom autoscroll increments up once at start of gesture rather than on every display link event
            for (DraggingDestinationInfo *info in self.draggingDestinations) {
                // If destination supports autoscroll and provides custom increment values, use them
                if ([info.draggingDestination respondsToSelector:@selector(autoscrollVerticalIncrement)]) {
                    info.autoscrollVerticalIncrement = [(id<DraggingAutoscroll>)info.draggingDestination autoscrollVerticalIncrement];
                }
                if ([info.draggingDestination respondsToSelector:@selector(autoscrollHorizontalIncrement)]) {
                    info.autoscrollHorizontalIncrement = [(id<DraggingAutoscroll>)info.draggingDestination autoscrollHorizontalIncrement];
                }
            }
            
            [self startAutoscrollTimer];
            [self.draggingSource draggingSessionBegan:self.draggingSession];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            //SRLog(@"dragging changed:");
            CGPoint translation = [recognizer translationInView:self.draggingContainerView];
            // Reset to continue receiving delta values
            [recognizer setTranslation:CGPointZero inView:self.draggingContainerView];
            
            UIView *snapshot = [self.draggingSession.sessionDraggingInfo snapshotView];
            //SRLog(@"setting snapshot.center = {%@ + %@, %@ + %@}", @(snapshot.center.x), @(translation.x), @(snapshot.center.y), @(translation.y));
            snapshot.center = CGPointMake(snapshot.center.x + translation.x, snapshot.center.y + translation.y);
            
            [self.draggingSource draggingSession:self.draggingSession movedByAmount:translation];
            
            for (DraggingDestinationInfo *info in self.draggingDestinations) {
                //CGPoint locationInDestination = [recognizer locationInView:info.destinationView]; // if need touch pt instead of snapshot center
                CGPoint locationInDestination = [snapshot.superview convertPoint:snapshot.center toView:info.destinationView];
                self.draggingSession.sessionDraggingInfo.snapshotCenterInDestination = locationInDestination;
                // Check to see if the dragged view is within a destination view's bounds
                // TODO: I don't think I need pointInside:withEvent; why not just CGRectContainsPoint (seems to be same thing for this usage)
                // TODO: If you pan using the top edge of the snapshot and move it down far enough, the center will go outside the destination's bounds.
                // This results in draggingExited:. I can solve this by adding an intersectionRect to the draggingItem that's based around the center
                // (or handle it in <DraggingDestination> with a UIEdgeInsets to extend top/bottom
                // That wouldn't be ideal for situations where the destination view doesn't extend to the edge of the screen and you could end up
                // dragging within two destinations at once -- using a point as I'm currently doing ensures the snapshot is only in one view at a time.
                if ([info.destinationView pointInside:locationInDestination withEvent:nil]) {
                    if (info.dragIsInside) {
                        // Dragging is still inside the destination view
                        if ([info.draggingDestination respondsToSelector:@selector(autoscrollView)]) {
                            id<DraggingAutoscroll> autoscrollable = (id<DraggingAutoscroll>)info.draggingDestination;
                            info.autoscrollDirection = [self autoscrollDirectionForAutoscrollable:autoscrollable];
                            //SRLog(@"autoscroll dir is: %@", [self stringForAutoscrollDirectionOptions:info.autoscrollDirection]);
                        }
                        info.dragOperation = [info.draggingDestination draggingUpdated:self.draggingSession.sessionDraggingInfo];
                        
                    } else {
                        // Dragging is inside destination view and it wasn't previously; entered
                        info.dragIsInside = YES;
                        info.dragOperation = [info.draggingDestination draggingEntered:self.draggingSession.sessionDraggingInfo];
                    }
                    
                } else {
                    // Dragging is not inside destination view; if it previously was, this means it exited
                    if (info.dragIsInside) {
                        info.dragIsInside = NO;
                        info.autoscrollDirection = AutoscrollDirectionNone;
                        info.dragOperation = DragOperationNone;
                        [info.draggingDestination draggingExited:self.draggingSession.sessionDraggingInfo];
                    }
                }
            }
            break;
        }
        case UIGestureRecognizerStateCancelled: {
            SRLog(@"dragging cancelled");
            [self stopAutoscrollTimer];
            [self endDraggingSession];
            break;
        }
        case UIGestureRecognizerStateEnded: {
            SRLog(@"dragging ended");
            [self stopAutoscrollTimer];
            [self endDraggingSession];
            break;
        }
        default:
            break;
    }
}

@end