//
//  XLDAmazonSearcher.m
//  XLD
//
//  Created by tmkk on 11/05/17.
//  Copyright 2011 tmkk. All rights reserved.
//

#import "XLDAmazonSearcher.h"
//#import <openssl/sha.h>
#import <openssl/bio.h>
#import <openssl/evp.h>
#import <openssl/buffer.h>
#import <CommonCrypto/CommonDigest.h>
#import "XLDCustomClasses.h"

enum
{
	AWSNone = 0,
	AWSReadingItem,
	AWSReadingASIN,
	AWSReadingLargeImage,
	AWSReadingMediumImage,
	AWSReadingSmallImage,
	AWSReadingItemAttrs,
	AWSReadingImageSets,
	AWSReadingVariantLargeImage,
	AWSReadingVariantMediumImage,
	AWSReadingVariantSmallImage,
	AWSReadingErrorResponse,
};

const char *server1 = "ecs.amazonaws";
const char *server2 = "webservices.amazon"; // new server for .es, .it, .cn, .com

typedef struct
{
	CC_SHA256_CTX sha;
	unsigned char keybuf[64];
} hmac_sha256_t;

/*
 HMAC is
 hash( (key ^ 0x5c) || hash( (key ^ 0x36) || data ) )
 */

static void HMAC_SHA256_Init(hmac_sha256_t *hmac, const void *key, int length)
{
	int i;
	if(length > 64) {
		unsigned char digest[32];
		CC_SHA256_CTX sha;
		CC_SHA256_Init(&sha);
		CC_SHA256_Update(&sha,key,length);
		CC_SHA256_Final(digest,&sha);
		memcpy(hmac->keybuf,digest,32);
		length = 32;
	}
	else memcpy(hmac->keybuf,key,length);
	for(i=length;i<64;i++) hmac->keybuf[i] = 0;
	for(i=0;i<64;i++) hmac->keybuf[i] ^= 0x36;
	CC_SHA256_Init(&hmac->sha);
	CC_SHA256_Update(&hmac->sha,hmac->keybuf,64);
}

static void HMAC_SHA256_Update(hmac_sha256_t *hmac, const unsigned char *data, int length)
{
	CC_SHA256_Update(&hmac->sha,data,length);
}

static void HMAC_SHA256_Final(hmac_sha256_t *hmac, unsigned char *md)
{
	int i;
	CC_SHA256_Final(md,&hmac->sha);
	CC_SHA256_CTX sha;
	CC_SHA256_Init(&sha);
	for(i=0;i<64;i++) hmac->keybuf[i] ^= 0x36 ^ 0x5c;
	CC_SHA256_Update(&sha,hmac->keybuf,64);
	CC_SHA256_Update(&sha,md,32);
	CC_SHA256_Final(md,&sha);
}

static char *base64enc(const unsigned char *input, int length)
{
	BIO *bmem, *b64;
	BUF_MEM *bptr;
	
	b64 = BIO_new(BIO_f_base64());
	BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
	bmem = BIO_new(BIO_s_mem());
	b64 = BIO_push(b64, bmem);
	BIO_write(b64, input, length);
	BIO_flush(b64);
	BIO_get_mem_ptr(b64, &bptr);
	
	char *buff = (char *)malloc(bptr->length+1);
	memcpy(buff, bptr->data, bptr->length);
	buff[bptr->length] = 0;
	
	BIO_free_all(b64);
	
	return buff;
}

@implementation XLDAmazonSearcher

- (NSString *)hmacDigestForArgs:(NSDictionary *)args
{
	NSArray *keys = [[args allKeys] sortedArrayUsingSelector:@selector(compare:)];
	NSMutableData *data = [NSMutableData data];
	[data appendBytes:"GET\n" length:4];
	[data appendBytes:server length:strlen(server)];
	[data appendBytes:domain length:strlen(domain)];
	[data appendBytes:"\n/onca/xml\n" length:11];
	int i;
	for(i=0;i<[keys count];i++) {
		[data appendData:[[NSString stringWithFormat:@"%@=%@",[keys objectAtIndex:i],[args objectForKey:[keys objectAtIndex:i]]] dataUsingEncoding:NSUTF8StringEncoding]];
		if(i!=[keys count]-1) [data appendBytes:"&" length:1];
	}
	
	unsigned char digest[128];
	hmac_sha256_t hmacsha;
	HMAC_SHA256_Init(&hmacsha,[secretKey UTF8String],[secretKey length]);
	HMAC_SHA256_Update(&hmacsha,[data bytes],[data length]);
	HMAC_SHA256_Final(&hmacsha,digest);
	char *digestStr = base64enc(digest,32);
	//NSLog(@"%s",digestStr);
	NSString *ret = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL,(CFStringRef)[NSString stringWithUTF8String:digestStr],NULL,CFSTR("+="),kCFStringEncodingUTF8);
	free(digestStr);
	return [ret autorelease];
}

- (id)init
{
	return [self initWithDomain:".com"];
}

- (id)initWithDomain:(const char *)d
{
	[super init];
	
	strcpy(domain,d);
	arguments = [[NSMutableDictionary alloc] init];
	[arguments setObject:@"AWSECommerceService" forKey:@"Service"];
	//[arguments setObject:@"2009-01-06" forKey:@"Version"];
	[arguments setObject:[[NSDate date] descriptionWithCalendarFormat:@"%Y-%m-%dT%H%%3A%M%%3A%SZ" timeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"] locale:nil] forKey:@"Timestamp"];
	[arguments setObject:@"Small%2CImages" forKey:@"ResponseGroup"];
	[arguments setObject:@"tmkk-22" forKey:@"AssociateTag"];
	if(!strcmp(".it",domain)||!strcmp(".es",domain)||!strcmp(".cn",domain)) {
		[arguments setObject:@"2011-08-01" forKey:@"Version"];
		strcpy(server,server2);
	}
	else strcpy(server,server1);
	itemArray = [[NSMutableArray alloc] init];
	
	return self;
}

- (void)dealloc
{
	[arguments release];
	if(asin) [asin release];
	if(secretKey) [secretKey release];
	if(imageURL) [imageURL release];
	[itemArray release];
	if(errorMsg) [errorMsg release];
	[super dealloc];
}

- (void)setBarcode:(NSString *)barcode
{
	BOOL UPCMode = NO;
	if([barcode isEqualToString:@"000000000000"] || [barcode isEqualToString:@"0000000000000"]) return;
	if([barcode length] == 12 || ([barcode length] == 13 && [barcode characterAtIndex:0] == '0')) {
		UPCMode = YES;
		if([barcode length] == 13) barcode = [barcode substringFromIndex:1];
	}
	[arguments setObject:@"ItemLookup" forKey:@"Operation"];
	[arguments setObject:UPCMode ? @"UPC" : @"EAN" forKey:@"IdType"];
	[arguments setObject:barcode forKey:@"ItemId"];
	[arguments setObject:@"All" forKey:@"SearchIndex"];
}

- (void)setASIN:(NSString *)str
{
	[arguments setObject:@"ItemLookup" forKey:@"Operation"];
	[arguments setObject:@"ASIN" forKey:@"IdType"];
	[arguments setObject:str forKey:@"ItemId"];
}

- (void)setKeyword:(NSString *)keyword
{
	NSString *encoded = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL,(CFStringRef)[keyword precomposedStringWithCanonicalMapping],NULL,CFSTR(";,/?:@&=+$#'!*()"),kCFStringEncodingUTF8);
	[arguments setObject:@"ItemSearch" forKey:@"Operation"];
	[arguments setObject:[encoded autorelease] forKey:@"Keywords"];
	[arguments setObject:@"All" forKey:@"SearchIndex"];
	keywordSearchMode = YES;
}

- (void)setItemPage:(int)n
{
	[arguments setObject:[NSString stringWithFormat:@"%d",n] forKey:@"ItemPage"];
}

- (void)setAccessKey:(NSString *)key andSecretKey:(NSString *)skey
{
	[arguments setObject:[key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey:@"AWSAccessKeyId"];
	secretKey = [[skey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] retain];
}

- (void)doSearch
{
	if(asin) return;
	if(!secretKey || [secretKey isEqualToString:@""]) return;
	
	[itemArray removeAllObjects];
	
	int i;
	NSMutableString *str = [NSMutableString stringWithFormat:@"http://%s%s/onca/xml?",server,domain];
	NSArray *keys = [[arguments allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for(i=0;i<[keys count];i++) {
		[str appendString:[NSString stringWithFormat:@"%@=%@",[keys objectAtIndex:i],[arguments objectForKey:[keys objectAtIndex:i]]]];
		[str appendString:@"&"];
	}
	[str appendString:[NSString stringWithFormat:@"Signature=%@",[self hmacDigestForArgs:arguments]]];
	//NSLog(@"%@",str);
	
	NSURL *url = [NSURL URLWithString:str];
	NSError *err;
	NSData *data = [NSData fastDataWithContentsOfURL:url error:&err];
	if(data) {
		NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
		[parser setDelegate:self];
		[parser parse];
		[parser release];
	}
	else {
		if(errorMsg) [errorMsg release];
		errorMsg = [[NSString alloc] initWithFormat:@"Network connection error: %@",[err localizedDescription]];
	}
}

- (NSString *)ASIN
{
	return asin;
}

- (NSURL *)imageURL
{
	return imageURL;
}

- (NSArray *)items
{
	return itemArray;
}

- (NSString *)errorMessage
{
	return errorMsg;
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	if(currentStr) {
		[currentStr appendString:string];
	}
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
	if(errorMsg) [errorMsg release];
	errorMsg = [[NSString alloc] initWithFormat:@"Parse error: %@",[parseError localizedDescription]];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict
{
	if(state == AWSNone && [elementName isEqualToString:@"Item"]) {
		if(keywordSearchMode) {
			currentDic = [[NSMutableDictionary alloc] init];
		}
		state = AWSReadingItem;
	}
	else if(state == AWSReadingItem && [elementName isEqualToString:@"ASIN"]) {
		if(currentDic || !asin) {
			currentStr = [[NSMutableString alloc] init];
			state = AWSReadingASIN;
		}
	}
	else if(state == AWSReadingItem && [elementName isEqualToString:@"LargeImage"]) {
		if(currentDic || !imageURL) {
			state = AWSReadingLargeImage;
		}
	}
	else if(state == AWSReadingLargeImage) {
		if([elementName isEqualToString:@"URL"] || [elementName isEqualToString:@"Height"] || [elementName isEqualToString:@"Width"]) {
			currentStr = [[NSMutableString alloc] init];
		}
	}
	else if(state == AWSReadingItem && [elementName isEqualToString:@"ItemAttributes"]) {
		state = AWSReadingItemAttrs;
	}
	else if(state == AWSReadingItemAttrs) {
		if([elementName isEqualToString:@"Artist"] || [elementName isEqualToString:@"Title"]) {
			currentStr = [[NSMutableString alloc] init];
		}
	}
	else if(state == AWSReadingItem && [elementName isEqualToString:@"MediumImage"]) {
		if(currentDic) {
			state = AWSReadingMediumImage;
		}
	}
	else if(state == AWSReadingItem && [elementName isEqualToString:@"SmallImage"]) {
		if(currentDic) {
			state = AWSReadingSmallImage;
		}
	}
	else if(state == AWSReadingSmallImage ||state == AWSReadingMediumImage) {
		if([elementName isEqualToString:@"URL"]) {
			currentStr = [[NSMutableString alloc] init];
		}
	}
	else if(state == AWSReadingItem && [elementName isEqualToString:@"ImageSets"]) {
		state = AWSReadingImageSets;
		if(currentDic) {
			variants = [[NSMutableArray alloc] init];
		}
	}
	else if(state == AWSReadingImageSets) {
		if(variants) {
			if([elementName isEqualToString:@"ImageSet"]) {
				if(attributeDict) {
					NSString *cat = [attributeDict objectForKey:@"Category"];
					if(cat && [cat isEqualToString:@"variant"]) variant = [[NSMutableDictionary alloc] init];
				}
			}
			else if([elementName isEqualToString:@"LargeImage"]) {
				if(variant) state = AWSReadingVariantLargeImage;
			}
			else if([elementName isEqualToString:@"MediumImage"]) {
				if(variant) state = AWSReadingVariantMediumImage;
			}
			else if([elementName isEqualToString:@"SmallImage"]) {
				if(variant) state = AWSReadingVariantSmallImage;
			}
		}
	}
	else if(state == AWSReadingVariantLargeImage) {
		if([elementName isEqualToString:@"URL"] || [elementName isEqualToString:@"Height"] || [elementName isEqualToString:@"Width"]) {
			currentStr = [[NSMutableString alloc] init];
		}
	}
	else if(state == AWSReadingVariantSmallImage ||state == AWSReadingVariantMediumImage) {
		if([elementName isEqualToString:@"URL"]) {
			currentStr = [[NSMutableString alloc] init];
		}
	}
	else if(state == AWSNone && [elementName isEqualToString:@"ItemSearchErrorResponse"]) {
		state = AWSReadingErrorResponse;
	}
	else if(state == AWSNone && [elementName isEqualToString:@"Errors"]) {
		state = AWSReadingErrorResponse;
	}
	else if(state == AWSReadingErrorResponse && [elementName isEqualToString:@"Message"]) {
		currentStr = [[NSMutableString alloc] init];
	}
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	if(state == AWSReadingItem && [elementName isEqualToString:@"Item"]) {
		if(currentDic) {
			[itemArray addObject:currentDic];
			[currentDic release];
			currentDic = nil;
		}
		state = AWSNone;
	}
	else if(state == AWSReadingASIN && [elementName isEqualToString:@"ASIN"]) {
		if(currentDic) {
			[currentDic setObject:currentStr forKey:@"ASIN"];
			if(!strcmp(domain,".jp")) [currentDic setObject:[NSURL URLWithString:[NSString stringWithFormat:@"http://amazon.jp/o/ASIN/%@/tmkk-22",currentStr]] forKey:@"AmazonURL"];
			else if(!strcmp(domain,".com")) [currentDic setObject:[NSURL URLWithString:[NSString stringWithFormat:@"http://www.amazon.com/dp/%@/?tag=xlosdec-20",currentStr]] forKey:@"AmazonURL"];
			[currentStr release];
		}
		else asin = currentStr;
		currentStr = nil;
		state = AWSReadingItem;
	}
	else if(state == AWSReadingLargeImage) {
		if([elementName isEqualToString:@"LargeImage"]) {
			state = AWSReadingItem;
		}
		else if(currentStr) {
			if(currentDic) {
				[currentDic setObject:[NSURL URLWithString:currentStr] forKey:elementName];
			}
			else if([elementName isEqualToString:@"URL"]) {
				imageURL = [[NSURL alloc] initWithString:currentStr];
			}
			[currentStr release];
			currentStr = nil;
		}
	}
	else if(state == AWSReadingMediumImage) {
		if([elementName isEqualToString:@"MediumImage"]) {
			state = AWSReadingItem;
		}
		else if(currentStr) {
			if(currentDic) {
				[currentDic setObject:[NSURL URLWithString:currentStr] forKey:@"MediumImage"];
			}
			[currentStr release];
			currentStr = nil;
		}
	}
	else if(state == AWSReadingSmallImage) {
		if([elementName isEqualToString:@"SmallImage"]) {
			state = AWSReadingItem;
		}
		else if(currentStr) {
			if(currentDic) {
				[currentDic setObject:[NSURL URLWithString:currentStr] forKey:@"SmallImage"];
			}
			[currentStr release];
			currentStr = nil;
		}
	}
	else if(state == AWSReadingItemAttrs) {
		if([elementName isEqualToString:@"ItemAttributes"]) {
			state = AWSReadingItem;
		}
		else if(currentStr) {
			if(currentDic) {
				NSMutableString *str = [currentDic objectForKey:elementName];
				if(str) {
					[str appendFormat:@", %@",currentStr];
					[currentDic setObject:str forKey:elementName];
				}
				else [currentDic setObject:currentStr forKey:elementName];
			}
			[currentStr release];
			currentStr = nil;
		}
	}
	else if(state == AWSReadingImageSets) {
		if([elementName isEqualToString:@"ImageSets"]) {
			state = AWSReadingItem;
			if(variants && currentDic) {
				if([variants count]) [currentDic setObject:variants forKey:@"Variants"];
				[variants release];
				variants = nil;
			}
		}
		else if([elementName isEqualToString:@"ImageSet"]) {
			if(variant) {
				if([variant objectForKey:@"URL"]) [variants addObject:variant];
				[variant release];
				variant = nil;
			}
		}
	}
	else if(state == AWSReadingVariantLargeImage) {
		if([elementName isEqualToString:@"LargeImage"]) {
			state = AWSReadingImageSets;
		}
		else if(currentStr) {
			if(variant) {
				[variant setObject:[NSURL URLWithString:currentStr] forKey:elementName];
			}
			[currentStr release];
			currentStr = nil;
		}
	}
	else if(state == AWSReadingVariantMediumImage) {
		if([elementName isEqualToString:@"MediumImage"]) {
			state = AWSReadingImageSets;
		}
		else if(currentStr) {
			if(variant) {
				[variant setObject:[NSURL URLWithString:currentStr] forKey:@"MediumImage"];
			}
			[currentStr release];
			currentStr = nil;
		}
	}
	else if(state == AWSReadingVariantSmallImage) {
		if([elementName isEqualToString:@"SmallImage"]) {
			state = AWSReadingImageSets;
		}
		else if(currentStr) {
			if(variant) {
				[variant setObject:[NSURL URLWithString:currentStr] forKey:@"SmallImage"];
			}
			[currentStr release];
			currentStr = nil;
		}
	}
	else if(state == AWSReadingErrorResponse) {
		if([elementName isEqualToString:@"Message"]) {
			if(currentStr) {
				if(errorMsg) [errorMsg release];
				errorMsg = currentStr;
				currentStr = nil;
			}
		}
		else if([elementName isEqualToString:@"ItemSearchErrorResponse"]) {
			state = AWSNone;
		}
		else if([elementName isEqualToString:@"Errors"]) {
			state = AWSNone;
		}
	}
}

@end

