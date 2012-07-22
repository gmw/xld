//
//  XLDCustomClasses.h
//  XLD
//
//  Created by tmkk on 09/02/14.
//  Copyright 2009 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface XLDView : NSView {
	int tag;
}

- (int)tag;
- (void)setTag:(int)t;

@end

@interface XLDTextView : NSTextView {
	id actionTarget;
}

- (NSMenu *)menuForEvent:(NSEvent *)event;
- (void)setActionTarget:(id)target;

@end

@interface NSImage (String)
+ (NSImage *)imageWithString:(NSString *)string withFont:(NSFont *)font withColor:(NSColor *)color;
@end

@interface NSSavePanel (__HackyBlizzardNewFolderCategory)
- (void)_setIncludeNewFolderButton:(BOOL)yn;
@end

@interface XLDButton : NSButton {
	int modifierFlags;
}

- (BOOL)commandKeyPressed;
- (BOOL)optionKeyPressed;
- (BOOL)shiftKeyPressed;

@end

@interface XLDTrackListUtil : NSObject {	
}

+ (NSString *)artistForTracks:(NSArray *)tracks;
+ (NSString *)artistForTracks:(NSArray *)tracks sameArtistForAllTracks:(BOOL*)allSame;
+ (NSString *)dateForTracks:(NSArray *)tracks;
+ (NSString *)genreForTracks:(NSArray *)tracks;
+ (NSString *)albumTitleForTracks:(NSArray *)tracks;
+ (NSMutableData *)cueDataForTracks:(NSArray *)tracks withFileName:(NSString *)filename appendBOM:(BOOL)appendBOM samplerate:(int)samplerate;
+ (NSMutableData *)nonCompliantCueDataForTracks:(NSArray *)trackList withFileNameArray:(NSArray *)filelist appendBOM:(BOOL)appendBOM gapStatus:(unsigned int)status samplerate:(int)samplerate;
+ (NSString *)gracenoteDiscIDForTracks:(NSArray *)tracks totalFrames:(xldoffset_t)totalFrames freeDBDiscID:(unsigned int)discid;
@end

@interface NSFileManager (HiddenMethod)
- (BOOL)_web_createDirectoryAtPathWithIntermediateDirectories:(NSString *)path attributes:(NSDictionary *)attributes;
#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5
- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary *)attributes error:(NSError **)error;
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
#endif
@end

@interface NSFileManager (DirectoryAdditions)
- (void)createDirectoryWithIntermediateDirectoryInPath:(NSString *)path;
- (NSArray *)directoryContentsAt:(NSString *)path;
@end

@interface NSMutableDictionary (NSUserDefaultsCompatibility)
- (void)setInteger:(int)value forKey:(NSString *)defaultName;
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName;
@end

@interface XLDSplitView : NSSplitView {
}
@end

#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5
@interface NSTableView (HighlightStyle)
- (void)setSelectionHighlightStyle:(int)selectionHighlightStyle;
@end
#endif

@interface XLDAdaptiveTexturedWindow : NSWindow {
}
@end

@interface NSWorkspace (IconAdditions)
- (NSImage *)iconForFolder;
- (NSImage *)iconForDisc;
- (NSImage *)iconForBurn;
@end

@interface NSData (FasterSynchronusDownload)
+ (NSData *)fastDataWithContentsOfURL:(NSURL *)url;
@end

@interface NSFlippedView : NSView {
}
@end

#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5
@interface NSWindow (BorderThickness)
- (void)setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge;
- (void)setContentBorderThickness:(float)thickness forEdge:(NSRectEdge)edge;
@end
#endif

@interface NSDate (XLDLocalizedDateDecription)
- (NSString *)localizedDateDescription;
@end

#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5
@interface NSCell (XLDCompatBackgroundStyle)
- (void)setBackgroundStyle:(int)style;
@end
#endif

#if MAC_OS_X_VERSION_MAX_ALLOWED < 1070
@interface NSScrollView (XLDOverlayScrollerExtra)
- (void)setScrollerKnobStyle:(long)newScrollerKnobStyle;
@end
#endif

@interface XLDBundle : NSBundle {
}
@end
