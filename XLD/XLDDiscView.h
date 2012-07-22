//
//  XLDDiscView.h
//  XLD
//
//  Created by tmkk on 11/03/06.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDDiscView : NSObject {
	IBOutlet id o_window;
	IBOutlet id o_selectorTable;
	IBOutlet id o_trackTable;
	IBOutlet id o_splitView;
	IBOutlet id o_imageView;
	IBOutlet id o_trackTableScroll;
	IBOutlet id o_extractionModeMenu;
	IBOutlet id o_accurateRipStatus;
	IBOutlet id o_titleText;
	IBOutlet id o_artistText;
	IBOutlet id o_verify;
	IBOutlet id o_totalTime;
	NSPopUpButton *o_extractionMode;
	
	id delegate;
	NSString *splitPosition;
	NSMutableDictionary *toolbarItems;
	NSMutableArray *parserArray;
	NSArray *checkArray;
	BOOL burning;
	id burner;
	BOOL checkUpdateStatus;
	int proposedRow;
}

- (IBAction)saveImage:(id)sender;
- (IBAction)openImage:(id)sender;
- (IBAction)checkSelected:(id)sender;
- (IBAction)uncheckSelected:(id)sender;
- (IBAction)editMetadata:(id)sender;
- (IBAction)clearImage:(id)sender;
- (IBAction)extractionModeChanged:(id)sender;
- (IBAction)verify:(id)sender;
- (void)openCueParser:(id)parser;
- (void)reloadData;
- (void)imageLoaded;
- (NSWindow *)window;
- (id)cueParser;
- (int)extractionMode;
- (void)setExtractionMode:(int)mode;
- (void)closeFile:(NSString *)path;
- (void)savePrefs;
- (void)loadPrefs;
- (BOOL)burning;
- (id)imageView;

@end
