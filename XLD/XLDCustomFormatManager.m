//
//  XLDCustomFormatManager.m
//  XLD
//
//  Created by tmkk on 10/10/21.
//  Copyright 2010 tmkk. All rights reserved.

#import "XLDCustomFormatManager.h"
#import "XLDoutput.h"

#define NSAppKitVersionNumber10_4 824

@implementation XLDCustomFormatManager

- (id)initWithOutputArray:(NSArray *)arr delegate:(id)del
{
	int i;
	[super init];
	delegate = [del retain];
	outputArray = [arr retain];
	configurationArray = [[NSMutableArray alloc] init];
	[NSBundle loadNibNamed:@"CustomFormatManager" owner:self];
	for(i=0;i<[outputArray count];i++) {
		[o_formatList addItemWithTitle:[[[outputArray objectAtIndex:i] class] pluginName]];
	}
	[o_tableView reloadData];
	[o_okButton setTarget:delegate];
	[o_okButton setAction:@selector(hideOption:)];
	[o_editButton setEnabled:NO];
	[o_deleteButton setEnabled:NO];
	//[o_mainWindow makeKeyAndOrderFront:self];
	return self;
}

- (void)dealloc
{
	[outputArray release];
	[configurationArray release];
	[delegate release];
	[super dealloc];
}

- (NSArray *)currentOutputArray
{
	NSMutableArray *arr = [[NSMutableArray alloc] init];
	int i,j;
	for(i=0;i<[configurationArray count];i++) {
		if([[[configurationArray objectAtIndex:i] objectForKey:@"Enabled"] boolValue]) {
			NSString *classStr = [[configurationArray objectAtIndex:i] objectForKey:@"ClassName"];
			for(j=0;j<[outputArray count];j++) {
				if([[[outputArray objectAtIndex:j] className] isEqualToString:classStr]) {
					[arr addObject:[outputArray objectAtIndex:j]];
					break;
				}
			}
		}
	}
	return [arr autorelease];
}

- (NSArray *)currentConfigurationsArray
{
	NSMutableArray *arr = [[NSMutableArray alloc] init];
	int i;
	for(i=0;i<[configurationArray count];i++) {
		if([[[configurationArray objectAtIndex:i] objectForKey:@"Enabled"] boolValue]) [arr addObject:[configurationArray objectAtIndex:i]];
	}
	return [arr autorelease];
}

- (id)panel
{
	return o_mainWindow;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setObject:configurationArray forKey:@"CustomFormatConfigurations"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	id obj;
	if(obj=[pref objectForKey:@"CustomFormatConfigurations"]) {
		int i;
		for(i=0;i<[obj count];i++) {
			NSMutableDictionary *mDic = [[obj objectAtIndex:i] mutableCopy];
			[configurationArray addObject:mDic];
			[mDic release];
		}
		[o_tableView reloadData];
	}
	else if(obj=[pref objectForKey:@"OutputFormatList"]) {
		int i,j;
		for(j=0;j<[obj count];j++) {
			for(i=0;i<[outputArray count];i++) {
				if([[[[outputArray objectAtIndex:i] class] pluginName] isEqualToString:[obj objectAtIndex:j]]) {
					id output = [outputArray objectAtIndex:i];
					NSString *name;
					NSMutableDictionary *cfg = [[(id <XLDOutput>)output configurations] mutableCopy];
					if([cfg objectForKey:@"ShortDesc"])
						name = [NSString stringWithFormat:@"%@ (%@)",[[output class] pluginName],[cfg objectForKey:@"ShortDesc"]];
					else
						name = [[output class] pluginName];
					[cfg setObject:name forKey:@"ConfigName"];
					[cfg setObject:[NSNumber numberWithBool:YES] forKey:@"Enabled"];
					[cfg setObject:[output className] forKey:@"ClassName"];
					[configurationArray addObject:cfg];
					[o_tableView reloadData];
					[cfg release];
					break;
				}
			}
		}
	}
	if(![configurationArray count]) {
		id output = [outputArray objectAtIndex:1];
		NSString *name;
		NSMutableDictionary *cfg = [[(id <XLDOutput>)output configurations] mutableCopy];
		if([cfg objectForKey:@"ShortDesc"])
			name = [NSString stringWithFormat:@"%@ (%@)",[[output class] pluginName],[cfg objectForKey:@"ShortDesc"]];
		else
			name = [[output class] pluginName];
		[cfg setObject:name forKey:@"ConfigName"];
		[cfg setObject:[NSNumber numberWithBool:YES] forKey:@"Enabled"];
		[cfg setObject:[output className] forKey:@"ClassName"];
		[configurationArray addObject:cfg];
		[o_tableView reloadData];
		[cfg release];
	}
}

- (NSArray *)descriptionMenuItems
{
	NSMutableArray *arr = [[NSMutableArray alloc] init];
	int i;
	[arr addObject:LS(@"Current encoders:")];
	for(i=0;i<[configurationArray count];i++) {
		if([[[configurationArray objectAtIndex:i] objectForKey:@"Enabled"] boolValue])
			[arr addObject:[NSString stringWithFormat:@"  - %@",[[configurationArray objectAtIndex:i] objectForKey:@"ConfigName"]]];
	}
	return [arr autorelease];
}

- (IBAction)addConfig:(id)sender
{
	id output = [outputArray objectAtIndex:[o_formatList indexOfSelectedItem]];
	NSView *view = [output prefPane];
	if(view) {
		NSRect frame = [view frame];
		frame.size.height += 50;
		[o_pluginPrefPane setContentSize:frame.size];
		if([[o_pluginOptionContentView subviews] count])
			[[[o_pluginOptionContentView subviews] objectAtIndex:0] removeFromSuperview];
		[o_pluginOptionContentView addSubview:view];
		[NSApp beginSheet:o_pluginPrefPane
		   modalForWindow:o_mainWindow
			modalDelegate:self
		   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
			  contextInfo:[[NSArray alloc] initWithObjects:@"AddItem",output,[output configurations],nil]];
		return;
	}
	
	NSMutableDictionary *cfg = [[(id <XLDOutput>)output configurations] mutableCopy];
	NSString *name,*orig;
	int i,duplicateCount=1;;
	if([cfg objectForKey:@"ShortDesc"])
		name = [NSString stringWithFormat:@"%@ (%@)",[[output class] pluginName],[cfg objectForKey:@"ShortDesc"]];
	else
		name = [[output class] pluginName];
	orig = name;
	for(i=0;i<[configurationArray count];i++) {
		if([[[configurationArray objectAtIndex:i] objectForKey:@"ConfigName"] isEqualToString:name]) {
			name = [NSString stringWithFormat:@"%@ (%d)",orig,duplicateCount++];
			i=-1;
		}
	}
	[cfg setObject:name forKey:@"ConfigName"];
	[cfg setObject:[NSNumber numberWithBool:YES] forKey:@"Enabled"];
	[cfg setObject:[output className] forKey:@"ClassName"];
	[configurationArray addObject:cfg];
	[o_tableView reloadData];
	[o_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:[configurationArray count]-1] byExtendingSelection:NO];
	[o_tableView editColumn:1 row:[configurationArray count]-1 withEvent:nil select:YES];
	[cfg release];
}

- (IBAction)deleteConfig:(id)sender
{
	int row = [o_tableView selectedRow];
	if(row < 0) return;
	if([configurationArray count] == 1) return;
	[configurationArray removeObjectAtIndex:row];
	if([configurationArray count] == 1) [[configurationArray objectAtIndex:0] setObject:[NSNumber numberWithBool:YES] forKey:@"Enabled"];
	[o_tableView reloadData];
}

- (IBAction)editConfig:(id)sender
{
	int row = [o_tableView selectedRow];
	if(row < 0) return;
	int i;
	NSView *view = nil;
	NSString *classStr = [[configurationArray objectAtIndex:row] objectForKey:@"ClassName"];
	id output;
	for(i=0;i<[outputArray count];i++) {
		if([[[outputArray objectAtIndex:i] className] isEqualToString:classStr]) {
			output = [outputArray objectAtIndex:i];
			view = [output prefPane];
			break;
		}
	}
	if(view) {
		NSRect frame = [view frame];
		frame.size.height += 50;
		[o_pluginPrefPane setContentSize:frame.size];
		if([[o_pluginOptionContentView subviews] count])
			[[[o_pluginOptionContentView subviews] objectAtIndex:0] removeFromSuperview];
		[o_pluginOptionContentView addSubview:view];
		id savedConfigurations = [output configurations];
		[output loadConfigurations:[configurationArray objectAtIndex:row]];
		[NSApp beginSheet:o_pluginPrefPane
		   modalForWindow:o_mainWindow
			modalDelegate:self
		   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
			  contextInfo:[[NSArray alloc] initWithObjects:@"EditItem",output,savedConfigurations,nil]];
	}
}

- (IBAction)hideOption:(id)sender
{
	[NSApp endSheet:[sender window] returnCode:[sender tag]];
	[[sender window] close];
	[o_mainWindow makeKeyAndOrderFront:self];
}

- (NSData *)configurations
{
	NSMutableData *data = [NSMutableData data];
	NSKeyedArchiver *encoder = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
	
	[encoder encodeObject:configurationArray forKey:@"CustomFormatConfigurations"];
	[encoder finishEncoding];
	[encoder release];
	return data;
}

- (void)loadConfigurations:(NSDictionary *)pref
{
	id obj;
	if(obj=[pref objectForKey:@"CustomFormatConfigurations"]) {
		NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingWithData:obj];
		NSArray *arr = [decoder decodeObjectForKey:@"CustomFormatConfigurations"];
		[decoder finishDecoding];
		[decoder release];
		
		[configurationArray removeAllObjects];
		[configurationArray addObjectsFromArray:arr];
		[o_tableView reloadData];
	}
}

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [configurationArray count];
}

- (id)tableView:(NSTableView *)tableView
		objectValueForTableColumn:(NSTableColumn *)tableColumn
			row:(int)row
{
	if([[tableColumn identifier] isEqualToString:@"Toggle"]) {
		return [[configurationArray objectAtIndex:row] objectForKey:@"Enabled"];
	}
	else if([[tableColumn identifier] isEqualToString:@"Name"]) {
		return [[configurationArray objectAtIndex:row] objectForKey:@"ConfigName"];
	}
	else return nil;
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
	if([[tableColumn identifier] isEqualToString:@"Toggle"]) {
		int enabledCount = 0;
		for(i=0;i<[configurationArray count];i++) {
			if([[[configurationArray objectAtIndex:i] objectForKey:@"Enabled"] boolValue]) enabledCount++;
		}
		if(enabledCount < 2) [[configurationArray objectAtIndex:row] setObject:[NSNumber numberWithBool:YES] forKey:@"Enabled"];
		else [[configurationArray objectAtIndex:row] setObject:object forKey:@"Enabled"];
	}
	else if([[tableColumn identifier] isEqualToString:@"Name"]) {
		if([object isEqualToString:@""]) return;
		NSRange range = [object rangeOfString:@"/"];
		if(range.location != NSNotFound) {
			object = [NSMutableString stringWithString:object];
			[object replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:range];
		}
		range = [object rangeOfString:@":"];
		if(range.location != NSNotFound) {
			object = [NSMutableString stringWithString:object];
			[object replaceOccurrencesOfString:@":" withString:@"_" options:0 range:range];
		}
		int duplicateCount=1;
		id orig = object;
		for(i=0;i<[configurationArray count];i++) {
			if(i != row && [[[configurationArray objectAtIndex:i] objectForKey:@"ConfigName"] isEqualToString:object]) {
				object = [NSString stringWithFormat:@"%@ (%d)",orig,duplicateCount++];
				i=-1;
			}
		}
		[[configurationArray objectAtIndex:row] setObject:object forKey:@"ConfigName"];
		if(floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_4) {
			[self performSelector:@selector(forceEndEditing:) withObject:o_tableView afterDelay: 0];
		}
	}
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if(!contextInfo) return;
	id output = [(NSArray *)contextInfo objectAtIndex:1];
	if(returnCode == 0) {
		NSMutableDictionary *cfg = [(id <XLDOutput>)output configurations];
		if([[(NSArray *)contextInfo objectAtIndex:0] isEqualToString:@"AddItem"]) {
			NSString *name,*orig;
			int i,duplicateCount=1;;
			if([cfg objectForKey:@"ShortDesc"])
				name = [NSString stringWithFormat:@"%@ (%@)",[[output class] pluginName],[cfg objectForKey:@"ShortDesc"]];
			else
				name = [[output class] pluginName];
			orig = name;
			for(i=0;i<[configurationArray count];i++) {
				if([[[configurationArray objectAtIndex:i] objectForKey:@"ConfigName"] isEqualToString:name]) {
					name = [NSString stringWithFormat:@"%@ (%d)",orig,duplicateCount++];
					i=-1;
				}
			}
			[cfg setObject:name forKey:@"ConfigName"];
			[cfg setObject:[NSNumber numberWithBool:YES] forKey:@"Enabled"];
			[cfg setObject:[output className] forKey:@"ClassName"];
			[configurationArray addObject:cfg];
			[o_tableView reloadData];
			[o_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:[configurationArray count]-1] byExtendingSelection:NO];
			[o_tableView editColumn:1 row:[configurationArray count]-1 withEvent:nil select:YES];
		}
		else if([[(NSArray *)contextInfo objectAtIndex:0] isEqualToString:@"EditItem"]) {
			int row = [o_tableView selectedRow];
			[cfg setObject:[[configurationArray objectAtIndex:row] objectForKey:@"ConfigName"] forKey:@"ConfigName"];
			[cfg setObject:[[configurationArray objectAtIndex:row] objectForKey:@"Enabled"] forKey:@"Enabled"];
			[cfg setObject:[[configurationArray objectAtIndex:row] objectForKey:@"ClassName"] forKey:@"ClassName"];
			[[configurationArray objectAtIndex:row] setDictionary:cfg];
			[o_tableView reloadData];
		}
	}
	[output loadConfigurations:[(NSArray *)contextInfo objectAtIndex:2]];
	[(id)contextInfo release];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if([o_tableView selectedRow] < 0) {
		[o_editButton setEnabled:NO];
		[o_deleteButton setEnabled:NO];
	}
	else {
		[o_editButton setEnabled:YES];
		if([configurationArray count] < 2)
			[o_deleteButton setEnabled:NO];
		else [o_deleteButton setEnabled:YES];
	}
}

@end

