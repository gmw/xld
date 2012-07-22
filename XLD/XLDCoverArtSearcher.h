//
//  XLDCoverArtSearcher.h
//  XLD
//
//  Created by tmkk on 11/05/20.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface XLDCoverArtSearcher : NSObject {
	IBOutlet id o_coverView;
	IBOutlet id o_scrollView;
	IBOutlet id o_window;
	id o_searchField;
	id o_messageField;
	id o_progress;
	NSMutableArray *views;
	NSMutableDictionary *toolbarItems;
	id delegate;
	BOOL decorated;
	NSMutableData *receiveData;
	NSURLConnection *connection;
	NSURL *alternateURL;
	BOOL loading;
	NSString *savePath;
}
- (id)initWithDelegate:(id)del;
- (IBAction)search:(id)sender;
- (void)showWindowWithKeyword:(NSString *)keyword;
@end
