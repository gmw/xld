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
}

- (IBAction)addToList:(id)sender;
- (IBAction)deleteFromList:(id)sender;
- (void)loadPrefs;
- (void)savePrefs;
- (void)replaceInvalidCharactersInMutableString:(NSMutableString *)str;

@end
