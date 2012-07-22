//
//  XLDMetadataEditor.h
//  XLD
//
//  Created by tmkk on 08/07/05.
//  Copyright 2008 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDMetadataEditor : NSObject {
	id delegate;
	NSArray *currentTracks;
	NSMutableArray *currentSingleTracks;
	NSMutableArray *currentTasks;
	NSMutableArray *currentRanges;
	int currentIndex;
	int currentSingleIndex;
	IBOutlet id o_trackEditor;
	IBOutlet id o_allEditor;
	IBOutlet id o_title;
	IBOutlet id o_artist;
	IBOutlet id o_album;
	IBOutlet id o_albumArtist;
	IBOutlet id o_genre;
	IBOutlet id o_composer;
	IBOutlet id o_year;
	IBOutlet id o_disc;
	IBOutlet id o_totalDisc;
	IBOutlet id o_comment;
	IBOutlet id o_compilation;
	IBOutlet id o_allTitle;
	IBOutlet id o_allArtist;
	IBOutlet id o_allAlbum;
	IBOutlet id o_allAlbumArtist;
	IBOutlet id o_allGenre;
	IBOutlet id o_allComposer;
	IBOutlet id o_allYear;
	IBOutlet id o_allDisc;
	IBOutlet id o_allTotalDisc;
	IBOutlet id o_allComment;
	IBOutlet id o_allCompilation;
	IBOutlet id o_singleTitle;
	IBOutlet id o_singleArtist;
	IBOutlet id o_singleAlbum;
	IBOutlet id o_singleAlbumArtist;
	IBOutlet id o_singleGenre;
	IBOutlet id o_singleComposer;
	IBOutlet id o_singleYear;
	IBOutlet id o_singleDisc;
	IBOutlet id o_singleTotalDisc;
	IBOutlet id o_singleComment;
	IBOutlet id o_singleCompilation;
	IBOutlet id o_picture;
	IBOutlet id o_track;
	IBOutlet id o_totalTrack;
	IBOutlet id o_nextButton;
	IBOutlet id o_prevButton;
	IBOutlet id o_singleNextButton;
	IBOutlet id o_singlePrevButton;
	IBOutlet id o_totalDiscCheck;
	IBOutlet id o_checkArray;
	IBOutlet id o_singleEditor;
	IBOutlet id o_compilationCheck;
	IBOutlet id o_textParserWindow;
	IBOutlet id o_textParserFormat;
	IBOutlet id o_textParserOverwrite;
	IBOutlet id o_textParserText;
	IBOutlet id o_textParserMatching;
	id fieldEditor;
	BOOL modal;
}

- (id)initWithDelegate:(id)del;
- (void)editTracks:(NSArray *)tracks atIndex:(int)index;
- (void)editAllTracks:(NSArray *)tracks;
- (BOOL)editSingleTracks:(NSArray *)tracks atIndex:(int)index;
- (void)editSingleTracks:(NSArray *)tracks withAlbumRanges:(NSArray *)ranges andDispatchTasks:(NSArray *)tasks;
- (void)inputTagsFromText;
- (IBAction)endEdit:(id)sender;
- (IBAction)cancelEdit:(id)sender;
- (IBAction)nextTrack:(id)sender;
- (IBAction)prevTrack:(id)sender;
- (IBAction)nextSingleTrack:(id)sender;
- (IBAction)prevSingleTrack:(id)sender;
- (IBAction)textModified:(id)sender;
- (IBAction)clearImage:(id)sender;
- (IBAction)openCoverImage:(id)sender;
- (IBAction)selectionChanged:(id)sender;
- (IBAction)applyForAll:(id)sender;
- (IBAction)applyForAlbum:(id)sender;
- (IBAction)parse:(id)sender;
- (BOOL)editingSingleTags;
- (id)imageView;
- (void)imageLoaded;
@end
