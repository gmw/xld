#import "XLDPlayerSlider.h"

@implementation XLDPlayerSlider

- (id)init
{
	[super init];
	return self;
}

- (void)setMouseDownFlag:(BOOL)flag
{
	mouseDown = flag;
}

- (BOOL)mouseDownFlag
{
	return mouseDown;
}

- (void)mouseDown:(NSEvent *)theEvent
{
	if([self isEnabled]) mouseDown = YES;
	[super mouseDown:theEvent];
}

@end
