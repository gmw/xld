#import <Foundation/Foundation.h>

@protocol XLDOutput

+ (NSString *)pluginName;
+ (BOOL)canLoadThisBundle;
- (NSView *)prefPane;
- (void)savePrefs;
- (void)loadPrefs;
- (id)createTaskForOutput;
- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg;
- (NSMutableDictionary *)configurations;
- (void)loadConfigurations:(id)configurations;

@end