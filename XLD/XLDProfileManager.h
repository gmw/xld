//
//  XLDProfileManager.h
//  XLD
//
//  Created by tmkk on 11/02/27.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDProfileManager : NSObject {
	IBOutlet id o_tableView;
	IBOutlet id o_mainWindow;
	IBOutlet id o_deleteButton;
	NSMutableArray *configurationArray;
	id delegate;
}

+ (NSDictionary *)profileForName:(NSString *)name;
- (IBAction)addProfile:(id)sender;
- (IBAction)removeProfile:(id)sender;
- (IBAction)loadProfile:(id)sender;
- (IBAction)showProfileManager:(id)sender;
- (void)loadPrefs;
- (void)savePrefs;
- (id)initWithDelegate:(id)del;

@end
