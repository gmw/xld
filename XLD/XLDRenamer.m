//
//  XLDRenamer.m
//  XLD
//
//  Created by tmkk on 13/04/06.
//  Copyright 2013 tmkk. All rights reserved.
//

#import "XLDRenamer.h"
#define NSAppKitVersionNumber10_4 824

@implementation XLDRenamer

- (id)init
{
	self = [super init];
	if(!self) return nil;
	renameList = [[NSMutableArray alloc] init];
	renameMap = [[NSMutableDictionary alloc] init];
	[renameList addObject:@"/"];
	[renameList addObject:@":"];
	[renameMap setObject:LS(@"slash") forKey:@"/"];
	[renameMap setObject:LS(@"colon") forKey:@":"];
	
	return self;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setObject:renameList forKey:@"CharacterReplacementList"];
	[pref setObject:renameMap forKey:@"CharacterReplacementMap"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	id obj;
	if(obj=[pref objectForKey:@"CharacterReplacementList"]) {
		int i;
		NSDictionary *map = [pref objectForKey:@"CharacterReplacementMap"];
		if(!map) return;
		
		for(i=0;i<[obj count];i++) {
			NSString *character = [obj objectAtIndex:i];
			NSString *replaceWith = [map objectForKey:character];
			if(replaceWith) {
				if(![renameMap objectForKey:character])
					[renameList addObject:character];
				[renameMap setObject:replaceWith forKey:character];
			}
		}
		[o_renameList reloadData];
	}
}

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [renameList count];
}

- (id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(NSTableColumn *)tableColumn
			row:(int)row
{
	if([[tableColumn identifier] isEqualToString:@"Character"])
		return [renameList objectAtIndex:row];
	else
		return [renameMap objectForKey:[renameList objectAtIndex:row]];
}

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if([[aTableColumn identifier] isEqualToString:@"Character"] && rowIndex < 2)
		return NO;
	return YES;
}

- (void)forceEndEditing:(NSTableView*)tableView
{
	id window = [tableView window];
	if ([window makeFirstResponder:tableView])
		// should really select the edited row
		[tableView deselectAll:self];
	else
		// last resort
		[window endEditingFor:nil];
}

- (void)tableView:(NSTableView *)tableView
   setObjectValue:(id)object 
   forTableColumn:(NSTableColumn *)tableColumn 
			  row:(int)row;
{
	if([[tableColumn identifier] isEqualToString:@"Character"]) {
		int i;
		if([object isEqualToString:@""]) goto end;
		for(i=0;i<[renameList count];i++) {
			if(i==row) continue;
			if([[renameList objectAtIndex:i] isEqualToString:object]) {
				goto end;
			}
		}
		NSString *oldKey = [renameList objectAtIndex:row];
		NSString *oldValue = [renameMap objectForKey:oldKey];
		[renameList removeObjectAtIndex:row];
		[renameMap removeObjectForKey:oldKey];
		[renameList insertObject:object atIndex:row];
		[renameMap setObject:oldValue forKey:object];
	}
	else {
		NSRange range = [object rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@":/"]];
		if(range.location != NSNotFound) {
			goto end;
		}
		NSString *key = [renameList objectAtIndex:row];
		[renameMap removeObjectForKey:key];
		[renameMap setObject:object forKey:key];
	}
	[self savePrefs];
end:
	if(floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_4) {
		[self performSelector:@selector(forceEndEditing:) withObject:o_renameList afterDelay: 0];
	}
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if([o_renameList selectedRow] < 2) {
		[o_deleteButton setEnabled:NO];
	}
	else {
		[o_deleteButton setEnabled:YES];
	}
}

- (IBAction)addToList:(id)sender
{
	NSString *name=LS(@"New Character");
	int i,duplicateCount=1;
	NSString *orig = name;
	for(i=0;i<[renameList count];i++) {
		if([[renameList objectAtIndex:i] isEqualToString:name]) {
			name = [NSString stringWithFormat:@"%@ %d",orig,duplicateCount++];
			i=-1;
		}
	}
	[renameMap setObject:@"_" forKey:name];
	[renameList addObject:name];
	[o_renameList reloadData];
	[self savePrefs];
	[o_renameList selectRowIndexes:[NSIndexSet indexSetWithIndex:[renameList count]-1] byExtendingSelection:NO];
	[o_renameList editColumn:0 row:[renameList count]-1 withEvent:nil select:YES];
	[[o_renameList window] makeKeyAndOrderFront:self];
}

- (IBAction)deleteFromList:(id)sender
{
	if([o_renameList selectedRow] < 2) return;
	NSString *oldKey = [renameList objectAtIndex:[o_renameList selectedRow]];
	[renameList removeObjectAtIndex:[o_renameList selectedRow]];
	[renameMap removeObjectForKey:oldKey];
	[o_renameList reloadData];
	[self savePrefs];
}

- (void)replaceInvalidCharactersInMutableString:(NSMutableString *)str
{
	int i;
	for(i=0;i<[renameList count];i++) {
		NSString *character = [renameList objectAtIndex:i];
		[str replaceOccurrencesOfString:character withString:[renameMap objectForKey:character] options:0 range:NSMakeRange(0, [str length])];
	}
	[str replaceOccurrencesOfString:@"\0" withString:@"" options:0 range:NSMakeRange(0, [str length])];
}

@end
