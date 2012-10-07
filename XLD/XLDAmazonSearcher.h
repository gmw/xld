//
//  XLDAmazonSearcher.h
//  XLD
//
//  Created by tmkk on 11/05/17.
//  Copyright 2011 tmkk. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface XLDAmazonSearcher : NSObject {
	NSString *asin;
	NSMutableString *currentStr;
	char domain[32];
	char server[32];
	NSMutableDictionary *arguments;
	NSString *secretKey;
	NSURL *imageURL;
	int state;
	BOOL keywordSearchMode;
	NSMutableDictionary *currentDic;
	NSMutableArray *itemArray;
	NSMutableArray *variants;
	NSMutableDictionary *variant;
	NSString *errorMsg;
}

- (id)initWithDomain:(const char *)d;
- (void)setBarcode:(NSString *)barcode;
- (void)setASIN:(NSString *)str;
- (void)setKeyword:(NSString *)keyword;
- (void)setItemPage:(int)n;
- (void)setAccessKey:(NSString *)key andSecretKey:(NSString *)skey;
- (void)doSearch;
- (NSString *)ASIN;
- (NSURL *)imageURL;
- (NSArray *)items;
- (NSString *)errorMessage;

@end
