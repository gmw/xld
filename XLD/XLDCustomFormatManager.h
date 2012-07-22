//
//  XLDCustomFormatManager.h
//  XLD
//
//  Created by tmkk on 10/10/21.
//  Copyright 2010 tmkk. All rights reserved.

#import <Cocoa/Cocoa.h>

@interface XLDCustomFormatManager: NSObject {
	IBOutlet id o_formatList;
	IBOutlet id o_tableView;
	IBOutlet id o_mainWindow;
	IBOutlet id o_pluginPrefPane;
	IBOutlet id o_pluginOptionContentView;
	IBOutlet id o_editButton;
	IBOutlet id o_deleteButton;
	IBOutlet id o_okButton;
	NSArray *outputArray;
	NSMutableArray *configurationArray;
	id delegate;
}
- (id)initWithOutputArray:(NSArray *)arr delegate:(id)del;
- (NSArray *)currentOutputArray;
- (NSArray *)currentConfigurationsArray;
- (id)panel;
- (void)loadPrefs;
- (void)savePrefs;
- (NSArray *)descriptionMenuItems;
- (NSData *)configurations;
- (void)loadConfigurations:(NSDictionary *)pref;
- (IBAction)addConfig:(id)sender;
- (IBAction)deleteConfig:(id)sender;
- (IBAction)editConfig:(id)sender;
- (IBAction)hideOption:(id)sender;
@end
