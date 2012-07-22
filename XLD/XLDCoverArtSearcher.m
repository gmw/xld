//
//  XLDCoverArtSearcher.m
//  XLD
//
//  Created by tmkk on 11/05/20.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDCoverArtSearcher.h"
#import "XLDAmazonSearcher.h"
#import "XLDShadowedImageView.h"
#import "XLDController.h"
#import "XLDCustomClasses.h"

#ifndef NSAppKitVersionNumber10_4
#define NSAppKitVersionNumber10_4 824
#endif

typedef void * CGSConnection;
extern OSStatus CGSNewConnection(const void **attributes, CGSConnection * id);

@implementation XLDCoverArtSearcher

-(void)enableBlurForWindow:(NSWindow *)window
{
	CGSConnection thisConnection;
	unsigned int compositingFilter;
	
	/*
	 Compositing Types
	 
	 Under the window   = 1 <<  0
	 Over the window    = 1 <<  1
	 On the window      = 1 <<  2
	 */
	
	int compositingType = 1 << 0; // Under the window
	
	/* Make a new connection to CoreGraphics */
	CGSNewConnection(NULL, &thisConnection);
	
	/* Create a CoreImage filter and set it up */
	CGSNewCIFilterByName(thisConnection, (CFStringRef)@"CIGaussianBlur", &compositingFilter);
	NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:2.0] forKey:@"inputRadius"];
	CGSSetCIFilterValuesFromDictionary(thisConnection, compositingFilter, (CFDictionaryRef)options);
	
	/* Now apply the filter to the window */
	CGSAddWindowFilter(thisConnection, [window windowNumber], compositingFilter, compositingType);
}

- (id)initWithDelegate:(id)del
{
	[super init];
	[NSBundle loadNibNamed:@"CoverArtSearcher" owner:self];
	views = [[NSMutableArray alloc] init];
	[o_scrollView setDrawsBackground:NO];
	if(floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_4) {
		[o_window setBackgroundColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.7]];
	}
	else {
		[o_window setBackgroundColor:[NSColor colorWithCalibratedWhite:0.1 alpha:0.8]];
	}
	if([o_scrollView respondsToSelector:@selector(setScrollerKnobStyle:)]) {
		[o_scrollView setScrollerKnobStyle:2];
	}
	[o_window setOpaque:NO];
	
	o_searchField = [[NSSearchField alloc] init];
	[[o_searchField cell] setSendsWholeSearchString:YES];
	[[o_searchField cell] setScrollable:YES];
	[o_searchField setRecentsAutosaveName:@"XLDCoverArtSearcherRecentSearch"];
	NSMenu *menu = [[NSMenu alloc] init];
	NSMenuItem *menuItem = [[NSMenuItem alloc] init];
	[menuItem setTitle:@"Recent Searches"];
	[menuItem setTag:NSSearchFieldRecentsMenuItemTag];
	[menu addItem:menuItem];
	[menuItem release];
	[menu addItem:[NSMenuItem separatorItem]];
	menuItem = [[NSMenuItem alloc] init];
	[menuItem setTitle:LS(@"Clear Recent Searches")];
	[menuItem setTag:NSSearchFieldClearRecentsMenuItemTag];
	[menu addItem:menuItem];
	[menuItem release];
	menuItem = [[NSMenuItem alloc] init];
	[menuItem setTitle:LS(@"No Recent Searches")];
	[menuItem setTag:NSSearchFieldNoRecentsMenuItemTag];
	[menu addItem:menuItem];
	[menuItem release];
	[[o_searchField cell] setSearchMenuTemplate:menu];
	[menu release];
	
	o_messageField = [[NSTextField alloc] init];
	[o_messageField setBordered:NO];
	[o_messageField setDrawsBackground:NO];
	[o_messageField setEditable:NO];
	o_progress = [[NSProgressIndicator alloc] init];
	[o_progress setStyle:NSProgressIndicatorBarStyle];
	[o_progress setIndeterminate:NO];
	[o_progress setHidden:YES];
	
	toolbarItems = [[NSMutableDictionary alloc] init];
	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:@"Search"];
	[item setView:o_searchField];
	[item setMinSize:NSMakeSize(200,22)];
	[item setMaxSize:NSMakeSize(500,2)];
	[item setTarget:self];
	[item setAction:@selector(search:)];
	[toolbarItems setObject:item forKey:@"Search"];
	[item release];
	item = [[NSToolbarItem alloc] initWithItemIdentifier:@"Message"];
	[item setView:o_messageField];
	[item setMinSize:NSMakeSize(100,16)];
	[item setMaxSize:NSMakeSize(250,16)];
	[toolbarItems setObject:item forKey:@"Message"];
	[item release];
	item = [[NSToolbarItem alloc] initWithItemIdentifier:@"Progress"];
	[item setView:o_progress];
	[item setMinSize:NSMakeSize(50,20)];
	[item setMaxSize:NSMakeSize(200,20)];
	[toolbarItems setObject:item forKey:@"Progress"];
	[item release];
	
	NSToolbar *theBar = [[NSToolbar alloc] initWithIdentifier:@"XLDProgressToolbar"];
	[theBar setDelegate:self];
	[theBar setDisplayMode:NSToolbarDisplayModeIconOnly];
	[o_window setToolbar:theBar];
	[theBar release];
	
	delegate = [del retain];
	[[o_scrollView contentView] setNeedsDisplay:YES];
	[o_window makeFirstResponder:o_searchField];
	
	//[o_window makeKeyAndOrderFront:nil];
	
	return self;
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
	loading = NO;
}

- (void)dealloc
{
	[self abortLoading];
	[views release];
	[toolbarItems release];
	[delegate release];
	if(savePath) [savePath release];
	[super dealloc];
}

- (void)removeAllViews
{
	int i;
	for(i=0;i<[views count];i++) {
		[[[views objectAtIndex:i] objectForKey:@"Image"] removeFromSuperview];
		[[[views objectAtIndex:i] objectForKey:@"Title"] removeFromSuperview];
		[[[views objectAtIndex:i] objectForKey:@"Artist"] removeFromSuperview];
		[[[views objectAtIndex:i] objectForKey:@"More"] removeFromSuperview];
	}
	[views removeAllObjects];
	NSRect frame = [o_coverView frame];
	frame.size.height = [o_scrollView frame].size.height;
	[o_coverView setFrame:frame];
}

- (void)arrangeViews
{
	NSRect frame = [o_coverView frame];
	frame.origin.y = 0;
	//NSLog(@"%f,%f",frame.origin.x,frame.origin.y);
	int columns = (frame.size.width-20)/200;
	float elementWidth = (frame.size.width-20)/columns;
	float elementHeight = 220;
	
	if(![views count]) frame.size.height = 0;
	else frame.size.height = (ceil((float)[views count]/columns))*elementHeight+5;
	[o_coverView setFrame:frame];
	//NSLog(@"%f,%f",frame.size.width,frame.size.height);
	//NSLog(@"%f,%f",[o_scrollView frame].size.width,[o_scrollView frame].size.height);
	
	if(![views count]) return;
	
	int i;
	for(i=0;i<[views count];i++) {
		NSRect rect;
		rect.size.width = 150;
		rect.size.height = 150;
		rect.origin.x = (elementWidth-150)/2+elementWidth*(i%columns);
		rect.origin.y = elementHeight*(i/columns)+10;
		[[[views objectAtIndex:i] objectForKey:@"Image"] setFrame:rect];
		[o_coverView addSubview:[[views objectAtIndex:i] objectForKey:@"Image"]];
		rect.size.width = elementWidth - 20;
		rect.size.height = 16;
		rect.origin.x = 10+elementWidth*(i%columns);
		rect.origin.y = elementHeight*(i/columns)+10+150+5;
		[[[views objectAtIndex:i] objectForKey:@"Title"] setFrame:rect];
		[o_coverView addSubview:[[views objectAtIndex:i] objectForKey:@"Title"]];
		rect.origin.y = elementHeight*(i/columns)+10+150+5+16;
		[[[views objectAtIndex:i] objectForKey:@"Artist"] setFrame:rect];
		[o_coverView addSubview:[[views objectAtIndex:i] objectForKey:@"Artist"]];
		if([[views objectAtIndex:i] objectForKey:@"More"]) {
			rect.origin.x = (elementWidth-60)/2+elementWidth*(i%columns);
			rect.origin.y = elementHeight*(i/columns)+10+150+5+16+18;
			rect.size.width = 60;
			rect.size.height = 20;
			[[[views objectAtIndex:i] objectForKey:@"More"] setFrame:rect];
			[o_coverView addSubview:[[views objectAtIndex:i] objectForKey:@"More"]];
		}
	}
}

- (IBAction)search:(id)sender
{
	[self removeAllViews];
	[o_coverView displayIfNeeded];
	if([[sender stringValue] isEqualToString:@""]) return;
	
	XLDAmazonSearcher *searcher = [[XLDAmazonSearcher alloc] initWithDomain:[delegate awsDomain]];
	[searcher setAccessKey:[[delegate awsKeys] objectForKey:@"Key"] andSecretKey:[[delegate awsKeys] objectForKey:@"SecretKey"]];
	[searcher setKeyword:[sender stringValue]];
	[searcher doSearch];
	
	NSMutableArray *results = [NSMutableArray arrayWithArray:[searcher items]];
	if([results count] == 10) {
		[searcher setItemPage:2];
		[searcher doSearch];
		[results addObjectsFromArray:[searcher items]];
	}
	//NSLog(@"%@",[results description]);
	
	if(![results count]) [o_messageField setStringValue:LS(@"Not found")];
	else [o_messageField setStringValue:@""];

	int i;
	for(i=0;i<[results count];i++) {
		NSURL *url = [[results objectAtIndex:i] objectForKey:@"URL"];
		if(!url) continue;
		
		NSMutableDictionary *dic = [NSMutableDictionary dictionary];
		[dic setObject:url forKey:@"URL"];
		if([[results objectAtIndex:i] objectForKey:@"ASIN"])
			[dic setObject:[[results objectAtIndex:i] objectForKey:@"ASIN"] forKey:@"ASIN"];
		if([[results objectAtIndex:i] objectForKey:@"MediumImage"])
			url = [[results objectAtIndex:i] objectForKey:@"MediumImage"];
		[dic setObject:url forKey:@"DisplayURL"];
		
		NSString *title = [[results objectAtIndex:i] objectForKey:@"Title"];
		NSString *artist = [[results objectAtIndex:i] objectForKey:@"Artist"];
		
		NSRect rect;
		rect.origin.x = 0;
		rect.origin.y = 0;
		rect.size.width = 150;
		rect.size.height = 150;
		XLDShadowedImageView *view = [[XLDShadowedImageView alloc] initWithFrame:rect];
		[view setShadowColor:[NSColor blackColor]];
		[view setBorderColor:[NSColor blackColor]];
		[view setAutosetTooltip:NO];
		[view setAcceptClick:YES];
		[view setTarget:self];
		[view setAction:@selector(setImage:)];
		[view setAlternateAction:@selector(saveImage:)];
		[view setTag:[views count]];
		[view loadImageFromURL:url];
		[view setBadge:[NSString stringWithFormat:@"%@x%@",[[results objectAtIndex:i] objectForKey:@"Width"],[[results objectAtIndex:i] objectForKey:@"Height"]]];
		[dic setObject:view forKey:@"Image"];
		[view release];
		
		rect.size.width = 150;
		rect.size.height = 16;
		NSTextField *field1 = [[NSTextField alloc] initWithFrame:rect];
		[field1 setTextColor:[NSColor whiteColor]];
		[field1 setStringValue:title?title:@""];
		[field1 setAlignment:NSCenterTextAlignment];
		[field1 setBordered:NO];
		[field1 setDrawsBackground:NO];
		[[field1 cell] setLineBreakMode:NSLineBreakByTruncatingTail];
		[field1 setEditable:NO];
		[field1 setFont:[NSFont boldSystemFontOfSize:12]];
		[field1 setToolTip:title];
		NSTextField *field2 = [[NSTextField alloc] initWithFrame:rect];
		[field2 setTextColor:[NSColor whiteColor]];
		[field2 setStringValue:artist?artist:@""];
		[field2 setAlignment:NSCenterTextAlignment];
		[field2 setBordered:NO];
		[field2 setDrawsBackground:NO];
		[[field2 cell] setLineBreakMode:NSLineBreakByTruncatingTail];
		[field2 setEditable:NO];
		[field2 setFont:[NSFont systemFontOfSize:12]];
		[field2 setToolTip:artist];
		[dic setObject:field1 forKey:@"Title"];
		[dic setObject:field2 forKey:@"Artist"];
		[field1 release];
		[field2 release];
		if([[results objectAtIndex:i] objectForKey:@"Variants"]) {
			rect.size.width = 60;
			rect.size.height = 18;
			NSButton *button = [[NSButton alloc] initWithFrame:rect];
			[button setButtonType:NSMomentaryPushInButton];
			[button setBezelStyle:NSRoundRectBezelStyle];
			[button setTitle:@"More..."];
			[button setTag:[views count]];
			[button setFont:[NSFont systemFontOfSize:11]];
			[button setAction:@selector(showVariants:)];
			[button setTarget:self];
			[[button cell] setControlSize:NSSmallControlSize];
			[dic setObject:button forKey:@"More"];
			NSMutableArray *arr = [NSMutableArray arrayWithObject:[results objectAtIndex:i]];
			[arr addObjectsFromArray:[[results objectAtIndex:i] objectForKey:@"Variants"]];
			[dic setObject:arr forKey:@"Variants"];
			[button release];
		}
		
		[views addObject:dic];
	}
	[self arrangeViews];
	[o_coverView displayIfNeeded];
	NSScroller *verticalScroller = [o_scrollView verticalScroller];
	[verticalScroller setFloatValue:0 knobProportion:[verticalScroller knobProportion]];
	[[o_scrollView contentView] scrollToPoint:NSZeroPoint];
	[[o_scrollView contentView] setNeedsDisplay:YES];
	[searcher release];
}

- (IBAction)showVariants:(id)sender
{
	if([sender tag] >= [views count]) return;
	NSArray *results = [[[views objectAtIndex:[sender tag]] objectForKey:@"Variants"] retain];
	
	[self removeAllViews];
	[o_coverView displayIfNeeded];
	
	int i;
	for(i=0;i<[results count];i++) {
		NSURL *url = [[results objectAtIndex:i] objectForKey:@"URL"];
		if(!url) continue;
		
		NSMutableDictionary *dic = [NSMutableDictionary dictionary];
		[dic setObject:url forKey:@"URL"];
		if([[results objectAtIndex:0] objectForKey:@"ASIN"])
			[dic setObject:[[results objectAtIndex:0] objectForKey:@"ASIN"] forKey:@"ASIN"];
		if([[results objectAtIndex:i] objectForKey:@"MediumImage"])
			url = [[results objectAtIndex:i] objectForKey:@"MediumImage"];
		
		NSString *title = [[results objectAtIndex:0] objectForKey:@"Title"];
		NSString *artist = [[results objectAtIndex:0] objectForKey:@"Artist"];
		if(i>0) [dic setObject:[NSString stringWithFormat:@"PT%02d",i] forKey:@"Page"];
		
		NSRect rect;
		rect.origin.x = 0;
		rect.origin.y = 0;
		rect.size.width = 150;
		rect.size.height = 150;
		XLDShadowedImageView *view = [[XLDShadowedImageView alloc] initWithFrame:rect];
		[view setShadowColor:[NSColor blackColor]];
		[view setBorderColor:[NSColor blackColor]];
		[view setAutosetTooltip:NO];
		[view setAcceptClick:YES];
		[view setTarget:self];
		[view setAction:@selector(setImage:)];
		[view setAlternateAction:@selector(saveImage:)];
		[view setTag:[views count]];
		[view loadImageFromURL:url];
		[view setBadge:[NSString stringWithFormat:@"%@x%@",[[results objectAtIndex:i] objectForKey:@"Width"],[[results objectAtIndex:i] objectForKey:@"Height"]]];
		[dic setObject:view forKey:@"Image"];
		[view release];
		
		rect.size.width = 150;
		rect.size.height = 16;
		NSTextField *field1 = [[NSTextField alloc] initWithFrame:rect];
		[field1 setTextColor:[NSColor whiteColor]];
		[field1 setStringValue:title?title:@""];
		[field1 setAlignment:NSCenterTextAlignment];
		[field1 setBordered:NO];
		[field1 setDrawsBackground:NO];
		[[field1 cell] setLineBreakMode:NSLineBreakByTruncatingTail];
		[field1 setEditable:NO];
		[field1 setFont:[NSFont boldSystemFontOfSize:12]];
		[field1 setToolTip:title];
		NSTextField *field2 = [[NSTextField alloc] initWithFrame:rect];
		[field2 setTextColor:[NSColor whiteColor]];
		[field2 setStringValue:artist?artist:@""];
		[field2 setAlignment:NSCenterTextAlignment];
		[field2 setBordered:NO];
		[field2 setDrawsBackground:NO];
		[[field2 cell] setLineBreakMode:NSLineBreakByTruncatingTail];
		[field2 setEditable:NO];
		[field2 setFont:[NSFont systemFontOfSize:12]];
		[field2 setToolTip:artist];
		[dic setObject:field1 forKey:@"Title"];
		[dic setObject:field2 forKey:@"Artist"];
		[field1 release];
		[field2 release];
		
		[views addObject:dic];
	}
	[results release];
	
	[self arrangeViews];
	[o_coverView displayIfNeeded];
	NSScroller *verticalScroller = [o_scrollView verticalScroller];
	[verticalScroller setFloatValue:0 knobProportion:[verticalScroller knobProportion]];
	[[o_scrollView contentView] scrollToPoint:NSZeroPoint];
	[[o_scrollView contentView] setNeedsDisplay:YES];
}

- (void)showWindowWithKeyword:(NSString *)keyword
{
	if(keyword) [o_searchField setStringValue:keyword];
	[o_window makeKeyAndOrderFront:nil];
	if(keyword) [o_searchField performClick:nil];
}

- (void)downloadUsingASIN:(NSString *)asin andURL:(NSURL *)url andPage:(NSString *)page
{
	receiveData = [[NSMutableData alloc] initWithCapacity:0];
	[o_progress setIndeterminate:YES];
	[o_progress startAnimation:nil];
	[o_progress setHidden:NO];
	loading = YES;
	if(asin) {
		alternateURL = [url retain];
		NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://ecx.images-amazon.com/images/P/%@.00.%@._SCRMZZZZZZ_.jpg",asin,page]] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
		connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
	}
	else {
		NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
		connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
	}
}

- (void)saveImage:(id)sender
{
	if(loading) return;
	if([sender tag] >= [views count]) return;
	
	NSSavePanel *sv = [NSSavePanel savePanel];
	
	[sv setAllowedFileTypes:[NSArray arrayWithObjects:@"jpg",@"png",@"gif",nil]];
	
	int ret = [sv runModalForDirectory:nil file:@"cover.jpg"];
	if(ret != NSOKButton) return;
	savePath = [[sv filename] retain];
	
	NSString *asin = [[views objectAtIndex:[sender tag]] objectForKey:@"ASIN"];
	NSURL *url = [[views objectAtIndex:[sender tag]] objectForKey:@"URL"];
	NSString *page = [[views objectAtIndex:[sender tag]] objectForKey:@"Page"];
	if(!page) page = @"MAIN";
	[self downloadUsingASIN:asin andURL:url andPage:page];
}

- (void)setImage:(id)sender
{
	if(loading) return;
	XLDShadowedImageView *imageView = [delegate imageView];
	if(!imageView) return;
	if([sender tag] >= [views count]) return;
	
	/*NSString *asin = [[views objectAtIndex:[sender tag]] objectForKey:@"ASIN"];
	if(asin) [imageView loadImageFromASIN:asin andAlternateURL:[[views objectAtIndex:[sender tag]] objectForKey:@"URL"]];
	else [imageView loadImageFromURL:[[views objectAtIndex:[sender tag]] objectForKey:@"URL"]];*/
	NSString *asin = [[views objectAtIndex:[sender tag]] objectForKey:@"ASIN"];
	NSURL *url = [[views objectAtIndex:[sender tag]] objectForKey:@"URL"];
	NSString *page = [[views objectAtIndex:[sender tag]] objectForKey:@"Page"];
	if(!page) page = @"MAIN";
	[self downloadUsingASIN:asin andURL:url andPage:page];
}

- (void)windowDidResize:(NSNotification *)aNotification
{
	[self arrangeViews];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	return [toolbarItems objectForKey:itemIdentifier];
}

-(NSArray *) toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
	return [NSArray arrayWithObjects:@"Search",@"Message",NSToolbarFlexibleSpaceItemIdentifier,@"Progress",nil];
}

-(NSArray *) toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
	return [NSArray arrayWithObjects:@"Search",@"Message",NSToolbarFlexibleSpaceItemIdentifier,@"Progress",nil];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
	return YES;
}

- (void)windowWillClose:(NSNotification *)aNotification
{
	[self removeAllViews];
	[o_searchField setStringValue:@""];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
	if(!decorated && floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_4) {
		[self enableBlurForWindow:o_window];
		decorated = YES;
	}
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
		receiveData = [[NSMutableData alloc] initWithCapacity:0];
		NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
		connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
		loading = YES;
		[url release];
	}
	else {
		[receiveData setLength:0];
		[o_progress setIndeterminate:NO];
		[o_progress stopAnimation:nil];
		[o_progress setMaxValue:length];
		[o_progress setDoubleValue:0];
	}
}

- (void)connection:(NSURLConnection *)conn didReceiveData:(NSData *)data
{
 	[receiveData appendData:data];
	[o_progress incrementBy:[data length]];
}

- (void)connection:(NSURLConnection *)conn didFailWithError:(NSError *)error
{
	[self abortLoading];
	if(alternateURL) {
		//NSLog(@"fail with error, retrying");
		NSURL *url = alternateURL;
		alternateURL = nil;
		receiveData = [[NSMutableData alloc] initWithCapacity:0];
		NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
		connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
		loading = YES;
		[url release];
	}
	else {
		if(savePath) {
			[savePath release];
			savePath = nil;
		}
		[o_progress stopAnimation:nil];
		[o_progress setHidden:YES];
	}
}

- (void)connectionDidFinishLoading:(NSURLConnection *)conn
{
	//NSLog(@"%@,%d",savePath,[receiveData length]);
	if(savePath) [receiveData writeToFile:savePath atomically:YES];
	else [delegate imageDataDownloaded:receiveData];
	
	if(alternateURL) {
		[alternateURL release];
		alternateURL = nil;
	}
	if(savePath) {
		[savePath release];
		savePath = nil;
	}
	[self abortLoading];
	[o_progress stopAnimation:nil];
	[o_progress setHidden:YES];
}

@end
