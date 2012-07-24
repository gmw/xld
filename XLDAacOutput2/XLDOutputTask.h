#import <Foundation/Foundation.h>

typedef struct
{
	int channels;
	int bps;
	int samplerate;
	int isFloat;
} XLDFormat;

@protocol XLDOutputTask

- (BOOL)setOutputFormat:(XLDFormat)fmt;
- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track;
- (NSString *)extensionStr;
- (BOOL)writeBuffer:(int *)buffer frames:(int)counts;
- (void)finalize;
- (void)closeFile;
- (void)setEnableAddTag:(BOOL)flag;

@end