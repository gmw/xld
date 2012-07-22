/* XLDPlayerSlider */

#import <Cocoa/Cocoa.h>

@interface XLDPlayerSlider : NSSlider
{
	BOOL mouseDown;
}
- (BOOL)mouseDownFlag;
- (void)setMouseDownFlag:(BOOL)flag;
@end
