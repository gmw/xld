//
//  XLDProfileManager.m
//  XLD
//
//  Created by tmkk on 11/02/27.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDProfileManager.h"
#import "XLDController.h"

#define TableRowType @"row"
#define TableRowTypes [NSArray arrayWithObjects:@"row",nil]
#define NSAppKitVersionNumber10_4 824

@implementation XLDProfileManager

+ (NSDictionary *)profileForName:(NSString *)name
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	id obj;
	if(obj=[pref objectForKey:@"Profiles"]) {
		int i;
		for(i=0;i<[obj count];i++) {
			NSDictionary *dic = [obj objectAtIndex:i];
			if([name isEqualToString:[dic objectForKey:@"XLDProfileManager_ProfileName"]]) {
				return dic;
			}
		}
	}
	return nil;
}

- (id)initWithDelegate:(id)del
{
	[super init];
	delegate = [del retain];
	configurationArray = [[NSMutableArray alloc] init];
	[NSBundle loadNibNamed:@"ProfileManager" owner:self];
	[o_tableView registerForDraggedTypes:TableRowTypes];
	[o_tableView reloadData];
	[o_deleteButton setEnabled:NO];
	return self;
}

- (NSArray *)profileNames
{
	int i;
	NSMutableArray *arr = [NSMutableArray array];
	for(i=0;i<[configurationArray count];i++) {
		[arr addObject:[[configurationArray objectAtIndex:i] objectForKey:@"XLDProfileManager_ProfileName"]];
	}
	return arr;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setObject:configurationArray forKey:@"Profiles"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	id obj;
	if(obj=[pref objectForKey:@"Profiles"]) {
		int i;
		for(i=0;i<[obj count];i++) {
			NSMutableDictionary *mDic = [[obj objectAtIndex:i] mutableCopy];
			[configurationArray addObject:mDic];
			[mDic release];
		}
		[o_tableView reloadData];
		[delegate updateProfileMenuFromNames:[self profileNames]];
	}
}

- (IBAction)addProfile:(id)sender
{
	NSMutableDictionary *cfg = [[delegate currentConfiguration] mutableCopy];
	NSString *name=LS(@"New Profile"),*orig=LS(@"New Profile");
	int i,duplicateCount=1;;
	for(i=0;i<[configurationArray count];i++) {
		if([[[configurationArray objectAtIndex:i] objectForKey:@"XLDProfileManager_ProfileName"] isEqualToString:name]) {
			name = [NSString stringWithFormat:@"%@ %d",orig,duplicateCount++];
			i=-1;
		}
	}
	[cfg setObject:name forKey:@"XLDProfileManager_ProfileName"];
	
	[configurationArray addObject:cfg];
	[o_tableView reloadData];
	[o_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:[configurationArray count]-1] byExtendingSelection:NO];
	[o_tableView editColumn:0 row:[configurationArray count]-1 withEvent:nil select:YES];
	[o_mainWindow makeKeyAndOrderFront:self];
	[delegate updateProfileMenuFromNames:[self profileNames]];
	[self savePrefs];
	[cfg release];
}

- (IBAction)removeProfile:(id)sender
{
	int row = [o_tableView selectedRow];
	if(row < 0 || row >= [configurationArray count]) return;
	[configurationArray removeObjectAtIndex:row];
	[o_tableView reloadData];
	[delegate updateProfileMenuFromNames:[self profileNames]];
}

- (IBAction)loadProfile:(id)sender
{
	NSDictionary *dic = nil;
	int i;
	for(i=0;i<[configurationArray count];i++) {
		if([[sender title] isEqualToString:[[configurationArray objectAtIndex:i] objectForKey:@"XLDProfileManager_ProfileName"]]) {
			dic = [configurationArray objectAtIndex:i];
			break;
		}
	}
	if(dic) [delegate loadProfileFromDictionary:dic];
}

- (IBAction)showProfileManager:(id)sender
{
	[o_mainWindow makeKeyAndOrderFront:nil];
}

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [configurationArray count];
}

- (id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(NSTableColumn *)tableColumn
			row:(int)row
{
	return [[configurationArray objectAtIndex:row] objectForKey:@"XLDProfileManager_ProfileName"];
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
	int i;
	
	int duplicateCount=1;
	id orig = object;
	if([object isEqualToString:@""]) return;
	for(i=0;i<[configurationArray count];i++) {
		if(i != row && [[[configurationArray objectAtIndex:i] objectForKey:@"XLDProfileManager_ProfileName"] isEqualToString:object]) {
			object = [NSString stringWithFormat:@"%@ (%d)",orig,duplicateCount++];
			i=-1;
		}
	}
	[[configurationArray objectAtIndex:row] setObject:object forKey:@"XLDProfileManager_ProfileName"];
	[delegate updateProfileMenuFromNames:[self profileNames]];
	[self savePrefs];
	if(floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_4) {
		[self performSelector:@selector(forceEndEditing:) withObject:o_tableView afterDelay: 0];
	}
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if([o_tableView selectedRow] < 0) {
		[o_deleteButton setEnabled:NO];
	}
	else {
		[o_deleteButton setEnabled:YES];
	}
}

-(BOOL)tableView:(NSTableView *)tv writeRows:(NSArray*)rows toPasteboard:(NSPasteboard*)pboard
{
	[pboard declareTypes:TableRowTypes owner:self];
	[pboard setPropertyList:rows forType:TableRowType];
	return YES;
}

-(NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)op
{
	NSPasteboard *pboard=[info draggingPasteboard];
	
	if (op == NSTableViewDropAbove && [pboard availableTypeFromArray:TableRowTypes] != nil) {
		return NSDragOperationGeneric;
	} else {
		return NSDragOperationNone;
	}
}

-(BOOL)tableView:(NSTableView*)tv acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)op
{
	NSPasteboard *pboard=[info draggingPasteboard];
	NSEnumerator *e=[[pboard propertyListForType:TableRowType] objectEnumerator];
	NSNumber *number;
	NSMutableArray *upperArray=[NSMutableArray arrayWithArray:[configurationArray subarrayWithRange:NSMakeRange(0,row)]];
	NSMutableArray *lowerArray=[NSMutableArray arrayWithArray:[configurationArray subarrayWithRange:NSMakeRange(row,([configurationArray count] - row))]];
	NSMutableArray *middleArray=[NSMutableArray arrayWithCapacity:0];
	id object;
	int i;
	
	if (op == NSTableViewDropAbove && [pboard availableTypeFromArray:TableRowTypes] != nil) {
		
		while ((number=[e nextObject]) != nil) {
			object=[configurationArray objectAtIndex:[number intValue]];
			[middleArray addObject:object];
			[upperArray removeObject:object];
			[lowerArray removeObject:object];
		}
		
		[configurationArray removeAllObjects];
		
		[configurationArray addObjectsFromArray:upperArray];
		[configurationArray addObjectsFromArray:middleArray];
		[configurationArray addObjectsFromArray:lowerArray];
		
		[o_tableView reloadData];
		[o_tableView deselectAll:nil];
		
		for (i=[upperArray count];i<([upperArray count] + [middleArray count]);i++) {
			[o_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:[o_tableView allowsMultipleSelection]];
		}
		[delegate updateProfileMenuFromNames:[self profileNames]];
		return YES;
	} else {
		return NO;
	}
}

@end
