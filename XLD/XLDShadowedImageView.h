//
//  XLDShadowedImageView.h
//  XLD
//
//  Created by tmkk on 11/03/05.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDShadowedImageView : NSView {
	NSImage *image;
	NSData *imageData;
	IBOutlet id delegate;
	NSMutableData *receiveData;
	NSURLConnection *connection;
	NSString *defaultString;
	NSColor *shadowColor;
	NSColor *borderColor;
	BOOL autosetTooltip;
	BOOL acceptClick;
	id actionTarget;
	SEL action;
	SEL alternateAction;
	int tag;
	BOOL loading;
	NSURL *alternateURL;
	BOOL ambiguous;
	NSString *badge;
}

- (BOOL)setImageData:(NSData *)data;
- (BOOL)setImageFromPath:(NSString *)path;
- (NSData *)imageData;
- (void)clearImage;
- (void)loadImageFromURL:(NSURL *)url;
- (void)loadImageFromASIN:(NSString *)asin andAlternateURL:(NSURL *)url;
- (void)setShadowColor:(NSColor *)c;
- (void)setBorderColor:(NSColor *)c;
- (void)setAutosetTooltip:(BOOL)f;
- (void)setAcceptClick:(BOOL)f;
- (void)setTarget:(id)obj;
- (void)setAction:(SEL)act;
- (void)setAlternateAction:(SEL)act;
- (void)setTag:(int)t;
- (int)tag;
- (void)setBadge:(NSString *)str;

@end
