//
//  XLDQueue.h
//  XLD
//
//  Created by tmkk on 07/11/17.
//  Copyright 2007 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDController.h"

@interface XLDQueue : NSObject {
	NSMutableArray *taskArr;
	NSMutableArray *progressViewArr;
	XLDController *delegate;
	NSLock *lock;
	int activeTask;
	NSMutableDictionary *toolbarItems;
	
	IBOutlet id o_mainPanel;
	IBOutlet id o_tableView;
	IBOutlet id o_menu;
	BOOL atomic;
	int lowestActivePosition;
	BOOL checkUpdateStatus;
	int selectedRow;
}

- (id)initWithDelegate:(id)del;
- (IBAction)test:(id)sender;
- (void)convertFinished:(id)task;
- (void)addTask:(id)task;
- (void)addTasks:(NSArray *)tasks;
- (void)showProgress;
- (IBAction)cancelAllTasks:(id)sender;
- (void)setMenuForItem:(id)item;
- (BOOL)hasActiveTask;

@end
