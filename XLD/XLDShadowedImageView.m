//
//  XLDShadowedImageView.m
//  XLD
//
//  Created by tmkk on 11/03/05.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDShadowedImageView.h"
#import "XLDDiscView.h"
#import "XLDCustomClasses.h"

@implementation XLDShadowedImageView

- (id)initWithFrame:(NSRect)rect
{
	[super initWithFrame:rect];
	NSArray* array = [NSArray arrayWithObjects:NSFilenamesPboardType,NSURLPboardType,nil];
	[self registerForDraggedTypes:array];
	shadowColor = [[[NSColor grayColor] colorWithAlphaComponent:0.3] retain];
	borderColor = [[NSColor darkGrayColor] retain];
	autosetTooltip = YES;
	return self;
}

- (void)drawRect:(NSRect)rect
{
	float viewWidth = [self frame].size.width;
	float viewHeight = [self frame].size.height;
	rect.origin.y = 0;
	rect.size.height = viewHeight;
	if(!image) {
		[NSGraphicsContext saveGraphicsState];
		NSShadow* shadow = [[NSShadow alloc] init];
		[shadow setShadowOffset:NSMakeSize(2.0, -2.0)];
		[shadow setShadowBlurRadius:5.0];
		[shadow setShadowColor:shadowColor];
		[shadow set];
		
		rect.origin.x += 5;
		rect.origin.y += 5;
		rect.size.width -= 10;
		rect.size.height -= 10;
		[[NSColor whiteColor] set];
		NSRectFill(rect);
		[NSGraphicsContext restoreGraphicsState];
		
		NSImage *imgStr = [NSImage imageWithString:defaultString?defaultString:@"No Image" withFont:[NSFont boldSystemFontOfSize:30] withColor:[NSColor lightGrayColor]];
		NSRect origRect = NSMakeRect(0, 0, [imgStr size].width, [imgStr size].height);
		NSRect newRect;
		newRect.size.width = viewWidth-20;
		newRect.size.height = [imgStr size].height*(viewHeight-20)/[imgStr size].width;
		newRect.origin.x = 10;
		newRect.origin.y = (viewHeight-newRect.size.height)*0.5;
		[imgStr drawInRect:newRect fromRect:origRect operation:NSCompositeSourceOver fraction:1.0];
		[borderColor set];
		NSFrameRect(rect);
		[shadow release];
	}
	else {
		int x = [image size].width;
		int y = [image size].height;
		NSPoint origin = NSMakePoint((viewWidth-x)/2.0, 5.0);
		[NSGraphicsContext saveGraphicsState];
		NSShadow* shadow = [[NSShadow alloc] init];
		[shadow setShadowOffset:NSMakeSize(2.0, -2.0)];
		[shadow setShadowBlurRadius:5.0];
		[shadow setShadowColor:shadowColor];
		[shadow set];
		[image drawAtPoint:origin fromRect:NSMakeRect(0, 0, x, y) operation:NSCompositeCopy fraction:1.0];
		[NSGraphicsContext restoreGraphicsState];
		[borderColor set];
		rect.origin.x = (viewWidth-x)/2.0;
		rect.origin.y = 5.0;
		rect.size.width = x;
		rect.size.height = y;
		NSFrameRect(rect);
		if(badge) {
			NSDictionary *attr = [NSDictionary dictionaryWithObjectsAndKeys:[NSColor whiteColor],NSForegroundColorAttributeName,[NSFont systemFontOfSize:9],NSFontAttributeName,nil];
			NSSize size = [badge sizeWithAttributes:attr];
			rect.origin.x += 1;
			rect.origin.y += 1;
			rect.size.width = size.width;
			rect.size.height = size.height;
			[[NSColor colorWithCalibratedWhite:0 alpha:0.5] set];
			NSRectFillUsingOperation(rect,NSCompositeSourceOver);
			[badge drawAtPoint:rect.origin withAttributes:attr];
		}
		[shadow release];
	}
}

- (void)resetCursorRects
{
	if(!acceptClick) return;
    NSRect rect = [self bounds];
    NSCursor* cursor = [NSCursor pointingHandCursor];
    [self addCursorRect:rect cursor:cursor];
}


- (void)setImage:(NSImage *)img
{
	//NSLog(@"%f,%f",[self frame].size.width,[self frame].size.height);
	float viewWidth = [self frame].size.width;
	float viewHeight = [self frame].size.height;
	if(image) [image release];
	image = nil;
	if(img) {
		int beforeX,beforeY,afterX,afterY;
		[img setCacheMode:NSImageCacheNever];
		NSImageRep *rep = [img bestRepresentationForDevice:nil];
		
		beforeX = [rep pixelsWide];
		beforeY = [rep pixelsHigh];
		if(beforeX > beforeY) {
			afterX = viewWidth-10;
			afterY = round((double)beforeY * (viewHeight-10)/beforeX);
		}
		else {
			afterX = round((double)beforeX * (viewWidth-10)/beforeY);
			afterY = viewHeight-10;
		}
		
		NSRect targetImageFrame = NSMakeRect(0,0,afterX,afterY);
		image = [[NSImage alloc] initWithSize:targetImageFrame.size];
		[image setCacheMode:NSImageCacheNever];
		[image lockFocus];
		[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
		[rep drawInRect: targetImageFrame];
		[image unlockFocus];
		if(autosetTooltip) [self setToolTip:[NSString stringWithFormat:@"%d x %d, %d KiB",beforeX,beforeY,[imageData length]/1024]];
	}
	else [self setToolTip:nil];
	[self display];
}

- (BOOL)setImageData:(NSData *)data
{
	BOOL ret = NO;
	if(!data) return ret;
	NSImage *img = [NSImage imageWithDataConsideringOrientation:data];
	if(img && [img isValid]) {
		if(imageData) [imageData release];
		imageData = [data retain];
		[self setImage:img];
		ret = YES;
	}
	//if(img) [img release];
	return ret;
}

- (NSData *)imageData
{
	return imageData;
}

- (void)clearImage
{
	if(imageData) [imageData release];
	imageData = nil;
	if(image) [image release];
	image = nil;
	[self setToolTip:nil];
	[self display];
}

- (void)setDefaultString:(NSString *)str
{
	if(defaultString) [defaultString release];
	defaultString = [str retain];
}

- (void)setBadge:(NSString *)str
{
	if(badge) [badge release];
	badge = [str retain];
}

- (void)loadImageFromURL:(NSURL *)url
{
	if(!url || loading) return;
	[self setDefaultString:@"Loading"];
	[self clearImage];
	receiveData = [[NSMutableData alloc] initWithCapacity:0];
	NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
	connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
	loading = YES;
}

- (void)loadImageFromASIN:(NSString *)asin andAlternateURL:(NSURL *)url
{
	if(!asin || !url || loading) return;
	[self setDefaultString:@"Loading"];
	[self clearImage];
	if([[url absoluteString] rangeOfString:@"LZZZZZZZ"].location != NSNotFound) ambiguous = YES;
	alternateURL = [url retain];
	receiveData = [[NSMutableData alloc] initWithCapacity:0];
	NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://ecx.images-amazon.com/images/P/%@.00._SCRMZZZZZZ_.jpg",asin]] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
	connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
	loading = YES;
}

- (void)abortLoading
{
	if(connection) {
		[connection cancel];
		[connection release];
		connection = nil;
	}
	if(receiveData) {
		[receiveData release];
		receiveData = nil;
	}
	if(defaultString) {
		[defaultString release];
		defaultString = nil;
	}
	loading = NO;
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
	/* explicit redirection is needed on OSX 10.4 */
	return request;
}

- (void)connection:(NSURLConnection *)conn didReceiveResponse:(NSURLResponse *)response
{
	int length = 0;
	length = [[[(NSHTTPURLResponse *)response allHeaderFields] objectForKey:@"Content-Length"] intValue];
	if(alternateURL && length < 10000) {
		//NSLog(@"fail, retrying");
		[self abortLoading];
		NSURL *url = alternateURL;
		alternateURL = nil;
		[self loadImageFromURL:url];
		[url release];
	}
	else [receiveData setLength:0];
	//NSLog(@"%@",[[(NSHTTPURLResponse *)response allHeaderFields] description]);
}

- (void)connection:(NSURLConnection *)conn didReceiveData:(NSData *)data
{
 	[receiveData appendData:data];
}

- (void)connection:(NSURLConnection *)conn didFailWithError:(NSError *)error
{
	[self abortLoading];
	if(alternateURL) {
		//NSLog(@"fail with error, retrying");
		NSURL *url = alternateURL;
		alternateURL = nil;
		[self loadImageFromURL:url];
		[url release];
	}
	else [self clearImage];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)conn
{
	if(alternateURL && [receiveData length] < 10000) {
		//NSLog(@"fail, retrying");
		[self abortLoading];
		NSURL *url = alternateURL;
		alternateURL = nil;
		[self loadImageFromURL:url];
		[url release];
	}
	else {
		BOOL success = NO;
		if(ambiguous && !alternateURL) {
			NSImage *img = [[NSImage alloc] initWithData:receiveData];
			if(img && [img isValid]) {
				if(([img size].width > 50) && ([img size].height > 50)) {
					success = [self setImageData:receiveData];
				}
			}
			if(img) [img release];
		}
		else success = [self setImageData:receiveData];
		if(success && delegate && [delegate respondsToSelector:@selector(imageLoaded)]) [delegate imageLoaded];
		if(alternateURL) {
			[alternateURL release];
			alternateURL = nil;
		}
		[self abortLoading];
		if(!success) [self clearImage];
	}
}

- (void)dealloc
{
	if(image) [image release];
	if(imageData) [imageData release];
	[self abortLoading];
	[shadowColor release];
	[borderColor release];
	if(actionTarget) [actionTarget release];
	if(alternateURL) [alternateURL release];
	if(defaultString) [defaultString release];
	if(badge) [badge release];
	[super dealloc];
}

- (void)setShadowColor:(NSColor *)c
{
	[shadowColor release];
	shadowColor = [c retain];
}

- (void)setBorderColor:(NSColor *)c
{
	[borderColor release];
	borderColor = [c retain];
}

- (void)setAutosetTooltip:(BOOL)f
{
	autosetTooltip = f;
}

- (void)setAcceptClick:(BOOL)f
{
	acceptClick = f;
}

- (void)mouseUp:(NSEvent *)theEvent
{
	if(!acceptClick) return;
	if([theEvent modifierFlags] & NSAlternateKeyMask) {
		if(actionTarget && alternateAction) [actionTarget performSelector:alternateAction withObject:self];
	}
	else if(actionTarget && action) {
		[actionTarget performSelector:action withObject:self];
	}
}

- (void)setTarget:(id)obj
{
	if(actionTarget) [actionTarget release];
	actionTarget = [obj retain];
}

- (void)setAction:(SEL)act
{
	action = act;
}

- (void)setAlternateAction:(SEL)act
{
	alternateAction = act;
}

- (void)setTag:(int)t
{
	tag = t;
}

- (int)tag
{
	return tag;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)info
{
	//if(!acceptDrag) return NSDragOperationNone;
	NSPasteboard *pboard = [info draggingPasteboard];
	if([[pboard types] containsObject:NSFilenamesPboardType]) {
		NSArray *fileArr = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
		if([fileArr count] != 1) return NSDragOperationNone;
		BOOL isDir;
		[[NSFileManager defaultManager] fileExistsAtPath:[fileArr objectAtIndex:0] isDirectory:&isDir];
		if(isDir) return NSDragOperationNone;
		
		if([NSCursor respondsToSelector:@selector(dragCopyCursor)])
			[[NSCursor performSelector:@selector(dragCopyCursor)] set];
		else [[NSCursor performSelector:@selector(_copyDragCursor)] set];
		return NSDragOperationGeneric;
	}
	else if([[pboard types] containsObject:NSURLPboardType]) {
		if([NSCursor respondsToSelector:@selector(dragCopyCursor)])
			[[NSCursor performSelector:@selector(dragCopyCursor)] set];
		else [[NSCursor performSelector:@selector(_copyDragCursor)] set];
		return NSDragOperationGeneric;
	}
	return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)info
{
	[[NSCursor arrowCursor] set];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)info
{
	NSData *dat = nil;
	NSPasteboard *pboard = [info draggingPasteboard];
	if([[pboard types] containsObject:NSFilenamesPboardType]) {
		NSString *path = [[[info draggingPasteboard] propertyListForType:NSFilenamesPboardType] objectAtIndex:0];
		NSFileManager *fm = [NSFileManager defaultManager];
		NSDictionary *attr = [fm fileAttributesAtPath:path traverseLink:YES];
		OSType type = [attr fileHFSTypeCode];
		if([[[path pathExtension] lowercaseString] isEqualToString:@"pictclipping"] || type == 'clpp') {
			FSRef fsRef;
			OSErr err;
			if(!FSPathMakeRef((UInt8*)[path UTF8String], &fsRef, NULL)) {
				ResFileRefNum resourceRef;
				HFSUniStr255 resourceForkName;
				UniCharCount forkNameLength;
				UniChar *forkName;
				err = FSGetResourceForkName(&resourceForkName);
				if(err) goto last;
				forkNameLength = resourceForkName.length;
				forkName = resourceForkName.unicode;
				err = FSOpenResourceFile(&fsRef, forkNameLength, forkName, (SInt8)fsRdPerm, &resourceRef);
				if(err) goto last;
				
				UseResFile(resourceRef);
				Handle rsrc = GetIndResource('PICT',1);
				if(rsrc) {
					HLock(rsrc);
					int resSize = GetHandleSize(rsrc);
					NSData *tmpData = [[NSData alloc] initWithBytes:*rsrc length:resSize];
					HUnlock(rsrc);
					ReleaseResource(rsrc);
					NSImage *tmpImg = [[NSImage alloc] initWithData:tmpData];
					if(tmpImg) {
						NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[tmpImg TIFFRepresentation]];
						dat = [[rep representationUsingType:NSPNGFileType properties:nil] retain];
						[tmpImg release];
					}
					[tmpData release];
				}
				CloseResFile(resourceRef);
			}
		}
	last:
		if(!dat) dat = [[NSData alloc] initWithContentsOfFile:path];
	}
	else if([[pboard types] containsObject:NSURLPboardType]) {
		dat = [[NSData alloc] initWithContentsOfURL:[NSURL URLFromPasteboard:pboard]];
	}
	return [self setImageData:[dat autorelease]];
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)info
{
	if(delegate && [delegate respondsToSelector:@selector(imageLoaded)]) [delegate imageLoaded];
}

@end
