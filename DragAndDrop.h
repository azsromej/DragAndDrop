//
//  DragAndDrop.h
//  StructuredPlan
//
//  Created by Steven Romej on 5/20/15.
//  Copyright (c) 2015 Steven Romej. All rights reserved.
//

@import Foundation;
@import UIKit;

@class DraggingItem;

typedef NS_OPTIONS(NSUInteger, AutoscrollDirection) {
    AutoscrollDirectionNone     = 0,        // 0000
    AutoscrollDirectionUp       = 1 << 0,   // 0001
    AutoscrollDirectionDown     = 1 << 1,   // 0010
    AutoscrollDirectionLeft     = 1 << 2,   // 0100
    AutoscrollDirectionRight    = 1 << 3    // 1000
};

// See UIViewAutoresizing enum for example of bitwise enum
typedef NS_OPTIONS(NSUInteger, DragOperation) {
    /// No drop operation allowed/available in destination
    DragOperationNone       = 0,
    /// Destination defines some kind of non-destructive action
    DragOperationGeneric    = 1 << 0,
    /// The dropped item will be deleted if dropped in destination
    DragOperationDelete     = 1 << 1
};

// --------------------------------------------------------------------------------
//
// <DraggingAutoscroll>
//
// --------------------------------------------------------------------------------
@protocol DraggingAutoscroll
- (UIEdgeInsets)autoscrollRegionInsets;
// NOTE: also consider examining view passed in registerDraggingDestination, assuming you'd never have a situation where
// you want to support drag/drop in the VC's view but also support autoscroll in a separate subview
- (UIScrollView *)autoscrollView;
- (void)autoscrollUpdatedInDirection:(AutoscrollDirection)direction location:(CGPoint)location;
@optional
- (CGFloat)autoscrollVerticalIncrement;
- (CGFloat)autoscrollHorizontalIncrement;
@end

// --------------------------------------------------------------------------------
//
// DraggingSession
//
// --------------------------------------------------------------------------------
@interface DraggingSession : NSObject

/// The actual dragged object that the dragged item represents
//@property (nonatomic, readonly) NSDictionary *draggedItemInfo;

@end

// --------------------------------------------------------------------------------
//
// <DraggingSource>
//
// --------------------------------------------------------------------------------
@protocol DraggingSource <NSObject>
/// The source can return a mask indicating the operations it allows to be performed.
/// On OSX, you might return None for operations outside your own app. That doesn't
/// make sense with this implementation, so you don't return .None from this (might
/// add something in the future to use that behavior though)
- (DragOperation)sourceOperationMaskForDraggingSession:(DraggingSession *)session;
/// Indicates dragging/panning started
- (void)draggingSessionBegan:(DraggingSession *)session;
/// Changes during dragging
- (void)draggingSession:(DraggingSession *)session movedByAmount:(CGPoint)translation;
/// Called after the finger lifts and after any drop animations are complete
- (void)draggingSessionEnded:(DraggingSession *)session operation:(DragOperation)operation;
@end

// --------------------------------------------------------------------------------
//
// <DraggingInfo>
//
// --------------------------------------------------------------------------------
/// An object conforming to this protocol is passed to a dragging destination and
/// is the way a destination interacts to a dragged item.
@protocol DraggingInfo <NSObject>
/// The snapshot view
- (UIView *)snapshotView;
/// The center of the snapshot view in destination view's coordinate system
- (CGPoint)snapshotCenterInDestination;
/// The dragging source
- (id<DraggingSource>)source;
/// Returns the dragging operation mask of the source
- (DragOperation)sourceOperationMask;
/// The actual dragged object
- (NSDictionary *)draggedItemInfo;
@end

// --------------------------------------------------------------------------------
//
// <DraggingDestination>
//
// --------------------------------------------------------------------------------
@protocol DraggingDestination <NSObject>
- (DragOperation)draggingEntered:(id<DraggingInfo>)info;
- (DragOperation)draggingUpdated:(id<DraggingInfo>)info;
- (void)draggingExited:(id<DraggingInfo>)info;
/// This is called on the destination if the last draggingEntered/Updated didn't return None
- (BOOL)prepareForDragOperation:(id<DraggingInfo>)info;
/// This is called if the destination returned YES in prepareForDragOperation:
/// Note that if you support <DraggingAnimation> it gets called after the animation.
- (void)completeDragOperation:(id<DraggingInfo>)info;
@end

// --------------------------------------------------------------------------------
//
// DraggingItem
//
// --------------------------------------------------------------------------------
@interface DraggingItem : NSObject
- (instancetype)initWithDraggedItemInfo:(NSDictionary *)info NS_DESIGNATED_INITIALIZER;
/// The view to use under finger while dragging
@property (nonatomic, strong) UIView *snapshotView;
@end

// --------------------------------------------------------------------------------
//
// <DraggingAnimationContext>
//
// --------------------------------------------------------------------------------
@protocol DraggingAnimationContext <NSObject>
- (UIView *)snapshotView;
/// Returns an object conforming to DraggingDestination, or nil if the drop wasn't accepted by a destination
- (id<DraggingDestination>)draggingDestination;
/// Returns the drag operation related to the destination (ie, you might animate a Delete different than a Generic drop).
/// The dragOperation only makes sense if there's a draggingDestination. It will be None if there is no destination.
- (DragOperation)dragOperation;
/// Returns the DraggingSource object for the current dragging session
- (id<DraggingSource>)draggingSource;
/// When implementing a custom lift or drop animation, this must be called.
/// It allows the dragging manager to do cleanup.
- (void)completeDraggingAnimation;
@end

// --------------------------------------------------------------------------------
//
// <DraggingAnimation>
//
// --------------------------------------------------------------------------------
@protocol DraggingAnimation <NSObject>
/// This is called on the DraggingSource object after a session is started to allow customization of the lift animation
- (void)animateDraggingLift:(id<DraggingAnimationContext>)context;
/// Called when a dragging session is ending to allow customization of the drop. If an object is accepted by
/// a destination, the destination handles the animation.
/// If it's not accepted, this is called on the source to allow it to animate the drop.
- (void)animateDraggingDrop:(id<DraggingAnimationContext>)context;
@end

// --------------------------------------------------------------------------------
//
// DraggingManager
///
// --------------------------------------------------------------------------------
@interface DraggingManager : NSObject

/// This is set when manageDraggingInView is called. It's the view that snapshot views are added to.
@property (nonatomic, weak, readonly) UIView *draggingContainerView;

/// Configures the dragging manager so that it can support dragging (panning) in the view.
/// The view can later be accessed by the draggingContainerView property.
- (void)manageDraggingInView:(UIView *)view;

/// The destination handles updates related to dragging within view.
/// The destination might be a view controller and view is a view the controller manages.
- (void)registerDraggingDestination:(id<DraggingDestination>)destination forView:(UIView *)view;


/// Starts a dragging session
- (DraggingSession *)startDraggingSessionWithItem:(DraggingItem *)item initialLongPressRecognizer:(UILongPressGestureRecognizer *)recognizer source:(id<DraggingSource>)source;

@end

