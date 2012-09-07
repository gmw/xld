/* XLDWavpackOutput */

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDWavpackOutput : NSObject <XLDOutput>
{
    IBOutlet id o_bitrate;
    IBOutlet id o_createCorrectionFile;
    IBOutlet id o_extraCompression;
    IBOutlet id o_mode;
    IBOutlet id o_quality;
    IBOutlet id o_text1;
    IBOutlet id o_text2;
	IBOutlet id o_text3;
	IBOutlet id o_text4;
	IBOutlet id o_text5;
	IBOutlet id o_prefView;
	IBOutlet id o_extraValue;
	IBOutlet id o_dns;
	IBOutlet id o_allowEmbeddedCuesheet;
}
+ (NSString *)pluginName;
+ (BOOL)canLoadThisBundle;
- (NSView *)prefPane;
- (void)savePrefs;
- (void)loadPrefs;
- (id)createTaskForOutput;
- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg;
- (NSMutableDictionary *)configurations;
- (void)loadConfigurations:(id)cfg;

- (IBAction)modeChanged:(id)sender;
- (IBAction)extraChecked:(id)sender;

@end
