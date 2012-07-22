#import "XLDPlayerWindow.h"
#import "XLDPlayer.h"

@implementation XLDPlayerWindow

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
	id fileArr = [[sender draggingPasteboard] propertyListForType:NSFilenamesPboardType];
	if([fileArr count] > 1) return NSDragOperationNone;
	
	if([NSCursor respondsToSelector:@selector(dragCopyCursor)])
		[[NSCursor performSelector:@selector(dragCopyCursor)] set];
	else [[NSCursor performSelector:@selector(_copyDragCursor)] set];
    return NSDragOperationGeneric;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
	id fileArr = [[sender draggingPasteboard] propertyListForType:NSFilenamesPboardType];
	if([fileArr count] > 1) return NSDragOperationNone;
	return NSDragOperationGeneric;
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
	return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	id fileArr = [[sender draggingPasteboard] propertyListForType:NSFilenamesPboardType];
	[[self delegate] openFileForPlay:[fileArr objectAtIndex:0]];
	return YES;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
	[[NSCursor arrowCursor] set];
}

@end
