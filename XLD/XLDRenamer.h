//
//  XLDRenamer.h
//  XLD
//
//  Created by tmkk on 13/04/06.
//  Copyright 2013 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDRenamer : NSObject {
	IBOutlet id o_renameList;
	IBOutlet id o_deleteButton;
	NSMutableArray *renameList;
	NSMutableDictionary *renameMap;
	NSMutableString *helper1;
	NSMutableString *helper2;
}

- (IBAction)addToList:(id)sender;
- (IBAction)deleteFromList:(id)sender;
- (void)loadPrefs;
- (void)savePrefs;
- (NSDictionary *)configurations;
- (void)loadConfigurations:(id)pref;
- (void)replaceInvalidCharactersInMutableString:(NSMutableString *)str;

@end
