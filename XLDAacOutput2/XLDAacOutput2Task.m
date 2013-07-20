//
//  XLDAacOutputTask.m
//  XLDAacOutput
//
//  Created by tmkk on 06/09/08.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDAacOutput2Task.h"
#import "XLDAacOutput2.h"

typedef int64_t xldoffset_t;

#import "XLDTrack.h"
#import <sys/stat.h>
#import <unistd.h>
#import <sys/types.h>

#ifdef _BIG_ENDIAN
#define SWAP32(n) (n)
#define SWAP16(n) (n)
#else
#define SWAP32(n) (((n>>24)&0xff) | ((n>>8)&0xff00) | ((n<<8)&0xff0000) | ((n<<24)&0xff000000))
#define SWAP16(n) (((n>>8)&0xff) | ((n<<8)&0xff00))
#endif

#define NSAppKitVersionNumber10_4 824

const unsigned int srTable[16]= {96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025,  8000,  7350,     0,     0,     0,};

static int getM4aFrequency(FILE *fp)
{
	char atom[4];
	int tmp,i;
	off_t initPos = ftello(fp);
	int freq = 0;
	
	if(fseeko(fp,0,SEEK_SET) != 0) goto end;
	
	while(1) { //skip until moov;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"moov",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until trak;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"trak",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until mdia;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"mdia",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until minf;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"minf",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until stbl;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"stbl",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until esds;
		if(fread(atom,1,4,fp) < 4) goto end;
		if(!memcmp(atom,"esds",4)) break;
		if(fseeko(fp,-3,SEEK_CUR) != 0) goto end;
	}
	
	if(fseeko(fp,5,SEEK_CUR) != 0) goto end;
	for(i=0;i<3;i++) {
		if(fread(atom,1,1,fp) < 1) goto end;
		if((unsigned char)atom[0] != 0x80) {
			if(fseeko(fp,-1,SEEK_CUR) != 0) goto end;
			break;
		}
	}
	if(fseeko(fp,5,SEEK_CUR) != 0) goto end;
	for(i=0;i<3;i++) {
		if(fread(atom,1,1,fp) < 1) goto end;
		if((unsigned char)atom[0] != 0x80) {
			if(fseeko(fp,-1,SEEK_CUR) != 0) goto end;
			break;
		}
	}
	if(fseeko(fp,15,SEEK_CUR) != 0) goto end;
	for(i=0;i<3;i++) {
		if(fread(atom,1,1,fp) < 1) goto end;
		if((unsigned char)atom[0] != 0x80) {
			if(fseeko(fp,-1,SEEK_CUR) != 0) goto end;
			break;
		}
	}
	if(fseeko(fp,1,SEEK_CUR) != 0) goto end;
	if(fread(atom,1,2,fp) < 2) goto end;
	tmp = (atom[0]<<1)&0xe;
	tmp |= (atom[1]>>7)&0x1;
	freq = srTable[tmp];
	
end:
		fseeko(fp,initPos,SEEK_SET);
	return freq;
}

static void appendUserDefinedComment(NSMutableData *tagData, NSString *tagIdentifier, NSString *commentStr)
{
	unsigned int tmp;
	unsigned char tmp3;
	NSData *commentData = [commentStr dataUsingEncoding:NSUTF8StringEncoding];
	NSData *tagIdentifierData = [tagIdentifier dataUsingEncoding:NSUTF8StringEncoding];
	tmp = 0x40 + [commentData length] + [tagIdentifierData length];
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"----" length:4];
	tmp = 0x1C;
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"mean" length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"com.apple.iTunes" length:16];
	tmp = 0xC + [tagIdentifierData length];
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"name" length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:4];
	[tagData appendData:tagIdentifierData];
	tmp = 0x10 + [commentData length];
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"data" length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:3]; //reserved
	tmp3 = 1;
	[tagData appendBytes:&tmp3 length:1]; //type (1:UTF-8)
	tmp = 0;
	[tagData appendBytes:&tmp length:4]; //locale (reserved to be 0)
	[tagData appendData:commentData];
}

static void appendTextTag(NSMutableData *tagData, const char *atomID, NSString *tagStr)
{
	unsigned int tmp;
	unsigned char tmp3;
	NSData *data = [tagStr dataUsingEncoding:NSUTF8StringEncoding];
	tmp = 24 + [data length];
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:atomID length:4];
	tmp = 16 + [data length];
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"data" length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:3]; //reserved
	tmp3 = 1;
	[tagData appendBytes:&tmp3 length:1]; //type (1:UTF-8)
	tmp = 0;
	[tagData appendBytes:&tmp length:4]; //locale (reserved to be 0)
	[tagData appendData:data];
}

static void appendNumericTag(NSMutableData *tagData, const char *atomID, NSNumber *tagNum, int length)
{
	if(length != 1 && length != 2 && length != 4) return;
	unsigned int tmp;
	unsigned short tmp2;
	unsigned char tmp3;
	tmp = 24 + length;
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:atomID length:4];
	tmp = 16 + length;
	tmp = NSSwapHostIntToBig(tmp);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:"data" length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:3]; //reserved
	tmp3 = 0x15;
	[tagData appendBytes:&tmp3 length:1]; //type (0x15:integer)
	tmp = 0;
	[tagData appendBytes:&tmp length:4]; //locale (reserved to be 0)
	if(length == 1) {
		tmp3 = [tagNum unsignedCharValue];
		[tagData appendBytes:&tmp3 length:1];
	}
	else if(length == 2) {
		tmp2 = NSSwapHostShortToBig([tagNum unsignedShortValue]);
		[tagData appendBytes:&tmp2 length:2];
	}
	else if(length == 4) {
		tmp = NSSwapHostIntToBig([tagNum unsignedIntValue]);
		[tagData appendBytes:&tmp length:4];
	}
}

NSMutableData *buildChapterTrack(unsigned int totalSamples, int samplerate, NSArray *trackList)
{
	NSMutableData *data = [NSMutableData data];
	NSMutableData *trefData = [NSMutableData data];
	int i;
	unsigned int tmp;
	unsigned short tmp2;
	unsigned char matrix[36] = {
		0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
		0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
		0x40,0x00,0x00,0x00
	};
	unsigned char lang[2] = {0x15,0xc7};
	NSDate *referenceDate = [NSDate dateWithString:@"1904-01-01 00:00:00 +0000"];
	unsigned int dateValue = [[NSDate date] timeIntervalSinceDate:referenceDate];
	int mdiaPos, minfPos, stblPos;
	NSMutableArray *sampleSizeArray = [NSMutableArray array];
	
	/* trak atom */
	[data appendBytes:&tmp length:4]; // update later
	[data appendBytes:"trak" length:4];
	/* tkhd atom */
	tmp = NSSwapHostIntToBig(0x5c);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"tkhd" length:4];
	tmp = NSSwapHostIntToBig(0xe);
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig(dateValue);
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig(2);
	[data appendBytes:&tmp length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig(totalSamples);
	[data appendBytes:&tmp length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:matrix length:36];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	/* mdia atom */
	mdiaPos = [data length];
	[data appendBytes:&tmp length:4]; // update later
	[data appendBytes:"mdia" length:4];
	/* mdhd atom */
	tmp = NSSwapHostIntToBig(0x20);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"mdhd" length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig(dateValue);
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig(samplerate);
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig(totalSamples);
	[data appendBytes:&tmp length:4];
	[data appendBytes:lang length:2];
	tmp = 0;
	[data appendBytes:&tmp length:2];
	/* hdlr atom */
	tmp = NSSwapHostIntToBig(0x21);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"hdlr" length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:"text" length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:1];
	/* minf atom */
	minfPos = [data length];
	[data appendBytes:&tmp length:4]; // update later
	[data appendBytes:"minf" length:4];
	/* gmhd atom */
	tmp = NSSwapHostIntToBig(0x4c);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"gmhd" length:4];
	/* gmin atom */
	tmp = NSSwapHostIntToBig(0x18);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"gmin" length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	tmp2 = NSSwapHostShortToBig(0x40);
	[data appendBytes:&tmp2 length:2];
	tmp2 = NSSwapHostShortToBig(0x8000);
	[data appendBytes:&tmp2 length:2];
	[data appendBytes:&tmp2 length:2];
	[data appendBytes:&tmp2 length:2];
	[data appendBytes:&tmp length:4];
	/* text atom */
	tmp = NSSwapHostIntToBig(0x2c);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"text" length:4];
	[data appendBytes:matrix length:36];
	/* dinf atom */
	tmp = NSSwapHostIntToBig(0x24);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"dinf" length:4];
	/* dref atom */
	tmp = NSSwapHostIntToBig(0x1c);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"dref" length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig(1);
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig(0xc);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"url " length:4];
	tmp = NSSwapHostIntToBig(1);
	[data appendBytes:&tmp length:4];
	/* stbl atom */
	stblPos = [data length];
	[data appendBytes:&tmp length:4]; // update later
	[data appendBytes:"stbl" length:4];
	/* stsd atom */
	tmp = NSSwapHostIntToBig(0x4b);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"stsd" length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig(1);
	[data appendBytes:&tmp length:4];
	/* text atom */
	tmp = NSSwapHostIntToBig(0x3b);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"text" length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:2];
	tmp2 = NSSwapHostShortToBig(1);
	[data appendBytes:&tmp2 length:2];
	tmp = NSSwapHostIntToBig(1);
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	tmp2 = 0;
	[data appendBytes:&tmp2 length:2];
	[data appendBytes:&tmp2 length:2];
	[data appendBytes:&tmp2 length:2];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:1];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	/* stts atom */
	tmp = NSSwapHostIntToBig(16+8*[trackList count]);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"stts" length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig([trackList count]);
	[data appendBytes:&tmp length:4];
	for(i=0;i<[trackList count];i++) {
		tmp = NSSwapHostIntToBig(1);
		[data appendBytes:&tmp length:4];
		/* track duration */
		int idx;
		int duration;
		if(i==0) idx = 0;
		else idx = [(XLDTrack *)[trackList objectAtIndex:i] index];
		if(i==[trackList count]-1) duration = totalSamples - idx;
		else duration = [(XLDTrack *)[trackList objectAtIndex:i+1] index] - idx;
		tmp = NSSwapHostIntToBig(duration);
		[data appendBytes:&tmp length:4];
	}
	/* stsz atom */
	tmp = NSSwapHostIntToBig(20+4*[trackList count]);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"stsz" length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig([trackList count]);
	[data appendBytes:&tmp length:4];
	for(i=0;i<[trackList count];i++) {
		/* sample length (UTF-8 length + 14) */
		const char *title;
		if([[(XLDTrack *)[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_TITLE])
			title = [[[(XLDTrack *)[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_TITLE] UTF8String];
		else title = [[NSString stringWithFormat:@"Track %d",i+1] UTF8String];
		[sampleSizeArray addObject:[NSNumber numberWithInt:strlen(title)+14]];
		tmp = NSSwapHostIntToBig(strlen(title)+14);
		[data appendBytes:&tmp length:4];
	}
	/* stsc atom */
	tmp = NSSwapHostIntToBig(0x1c);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"stsc" length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig(1);
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	[data appendBytes:&tmp length:4];
	/* stco atom */
	tmp = NSSwapHostIntToBig(16+4*[trackList count]);
	[data appendBytes:&tmp length:4];
	[data appendBytes:"stco" length:4];
	tmp = 0;
	[data appendBytes:&tmp length:4];
	tmp = NSSwapHostIntToBig([trackList count]);
	[data appendBytes:&tmp length:4];
	int offset = 8;
	for(i=0;i<[trackList count];i++) {
		/* sample offset - update later */
		tmp = NSSwapHostIntToBig(offset);
		[data appendBytes:&tmp length:4];
		offset += [[sampleSizeArray objectAtIndex:i] intValue];
	}
	
	/* update trak atom length */
	tmp = NSSwapHostIntToBig([data length]);
	[data replaceBytesInRange:NSMakeRange(0, 4) withBytes:&tmp];
	/* update mdia atom length */
	tmp = NSSwapHostIntToBig([data length]-mdiaPos);
	[data replaceBytesInRange:NSMakeRange(mdiaPos, 4) withBytes:&tmp];
	/* update minf atom length */
	tmp = NSSwapHostIntToBig([data length]-minfPos);
	[data replaceBytesInRange:NSMakeRange(minfPos, 4) withBytes:&tmp];
	/* update stbl atom length */
	tmp = NSSwapHostIntToBig([data length]-stblPos);
	[data replaceBytesInRange:NSMakeRange(stblPos, 4) withBytes:&tmp];
	
	/* tref atom */
	tmp = NSSwapHostIntToBig(0x14);
	[trefData appendBytes:&tmp length:4];
	[trefData appendBytes:"tref" length:4];
	/* chap atom */
	tmp = NSSwapHostIntToBig(0xc);
	[trefData appendBytes:&tmp length:4];
	[trefData appendBytes:"chap" length:4];
	tmp = NSSwapHostIntToBig(2);
	[trefData appendBytes:&tmp length:4];
	
	[trefData appendData:data];
	
	return trefData;
}

NSMutableData *buildChapterData(NSArray *trackList)
{
	NSMutableData *data = [NSMutableData data];
	int i;
	unsigned int tmp = 0;
	unsigned short tmp2 = 0;
	
	/* mdat atom */
	[data appendBytes:&tmp length:4];
	[data appendBytes:"mdat" length:4];
	for(i=0;i<[trackList count];i++) {
		const char *title;
		if([[(XLDTrack *)[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_TITLE])
			title = [[[(XLDTrack *)[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_TITLE] UTF8String];
		else title = [[NSString stringWithFormat:@"Track %d",i+1] UTF8String];
		tmp2 = NSSwapHostShortToBig(strlen(title));
		[data appendBytes:&tmp2 length:2];
		[data appendBytes:title length:strlen(title)];
		tmp = NSSwapHostIntToBig(0xc);
		[data appendBytes:&tmp length:4];
		[data appendBytes:"encd" length:4];
		tmp = NSSwapHostIntToBig(0x00000100);
		[data appendBytes:&tmp length:4];
	}
	
	/* update mdat atom length */
	tmp = NSSwapHostIntToBig([data length]);
	[data replaceBytesInRange:NSMakeRange(0, 4) withBytes:&tmp];
	
	return data;
}

@implementation XLDAacOutput2Task

- (id)init
{
	[super init];
	tagData = [[NSMutableData alloc] init];
	
	return self;
}

- (id)initWithConfigurations:(NSDictionary *)cfg
{
	[self init];
	configurations = [cfg retain];
	return self;
}

- (void)dealloc
{
	if(path) [path release];
	if(file) ExtAudioFileDispose(file);
	if(configurations) [configurations release];
	[tagData release];
	if(chapterMdat) [chapterMdat release];
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	format = fmt;
	
	if(format.bps > 4) return NO;
	
	inputFormat.mSampleRate = (Float64)format.samplerate;
	inputFormat.mFormatID = kAudioFormatLinearPCM;
	
#ifdef _BIG_ENDIAN
	if(format.isFloat) kAudioFormatFlagIsFloat|kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsPacked;
	else inputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsPacked;
#else
	if(format.isFloat) kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked;
	else inputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
#endif
	inputFormat.mFramesPerPacket = 1;
	inputFormat.mBytesPerFrame = 4 * format.channels;
	inputFormat.mBytesPerPacket = inputFormat.mBytesPerFrame;
	inputFormat.mChannelsPerFrame =  format.channels;
	inputFormat.mBitsPerChannel = 32;
	
	memset(&outputFormat,0,sizeof(AudioStreamBasicDescription));
	
	if([[configurations objectForKey:@"Samplerate"] intValue])
		outputFormat.mSampleRate = (Float64)[[configurations objectForKey:@"Samplerate"] intValue];
	
	if([[configurations objectForKey:@"SbrEnabled"] boolValue]) {
		sbrEnabled = YES;
		outputFormat.mFormatID = 'aach';
	}
	else {
		sbrEnabled = NO;
		outputFormat.mFormatID = kAudioFormatMPEG4AAC;
	}
	//outputFormat.mFormatFlags = kMPEG4Object_AAC_LC;
	//outputFormat.mBytesPerPacket = format.bps * format.channels;
	//outputFormat.mFramesPerPacket = 1;
	//outputFormat.mBytesPerFrame = outputFormat.mBytesPerPacket;
	outputFormat.mChannelsPerFrame = [[configurations objectForKey:@"ForceMono"] boolValue] ? 1 : format.channels;
	//outputFormat.mBitsPerChannel = format.bps << 3;
	
	return YES;
}

- (void)setupTagDataWithTrack:(id)track andEncoderAttr:(NSString *)encoderAttr
{
	BOOL added = NO;
	int tmp;
	short tmp2;
	char atomID[4];
	
	/* udta atom */
	tmp = 0;
	memcpy(atomID,"udta",4);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:atomID length:4];
	
	/* meta atom */
	tmp = 0;
	memcpy(atomID,"meta",4);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:atomID length:4];
	[tagData appendBytes:&tmp length:4];
	
	/* hdlr atom */
	tmp = 0x22;
	tmp = SWAP32(tmp);
	memcpy(atomID,"hdlr",4);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:atomID length:4];
	tmp = 0;
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:&tmp length:4];
	memcpy(atomID,"mdir",4);
	[tagData appendBytes:atomID length:4];
	memcpy(atomID,"appl",4);
	[tagData appendBytes:atomID length:4];
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:&tmp length:4];
	tmp2 = 0;
	tmp2 = SWAP16(tmp2);
	[tagData appendBytes:&tmp2 length:2];
	
	/* ilst atom */
	tmp = 0;
	memcpy(atomID,"ilst",4);
	[tagData appendBytes:&tmp length:4];
	[tagData appendBytes:atomID length:4];
	
	if(addTag) {
		/* nam atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"nam",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* ART atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"ART",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* aART atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST];
			appendTextTag(tagData, "aART", str);
		}
		
		/* alb atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"alb",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* gen atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"gen",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* wrt atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"wrt",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* trkn atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] || [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
			added = YES;
			tmp = 0x20;
			tmp = SWAP32(tmp);
			memcpy(atomID,"trkn",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			tmp = 0x18;
			tmp = SWAP32(tmp);
			memcpy(atomID,"data",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			tmp = 0;
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:&tmp length:4];
			tmp2 = 0;
			[tagData appendBytes:&tmp2 length:2];
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
				tmp2 = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] shortValue];
				tmp2 = SWAP16(tmp2);
			}
			[tagData appendBytes:&tmp2 length:2];
			tmp2 = 0;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
				tmp2 = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS] shortValue];
				tmp2 = SWAP16(tmp2);
			}
			[tagData appendBytes:&tmp2 length:2];
			tmp2 = 0;
			[tagData appendBytes:&tmp2 length:2];
		}
		
		/* disk atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] || [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
			added = YES;
			tmp = 0x1E;
			tmp = SWAP32(tmp);
			memcpy(atomID,"disk",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			tmp = 0x16;
			tmp = SWAP32(tmp);
			memcpy(atomID,"data",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			tmp = 0;
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:&tmp length:4];
			tmp2 = 0;
			[tagData appendBytes:&tmp2 length:2];
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC]) {
				tmp2 = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] shortValue];
				tmp2 = SWAP16(tmp2);
			}
			[tagData appendBytes:&tmp2 length:2];
			tmp2 = 0;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
				tmp2 = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS] shortValue];
				tmp2 = SWAP16(tmp2);
			}
			[tagData appendBytes:&tmp2 length:2];
		}
		
		/* day atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"day",3);
			appendTextTag(tagData, atomID, str);
		}
		else if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			added = YES;
			NSString *str = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] stringValue];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"day",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* cmt atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"cmt",3);
			appendTextTag(tagData, atomID, str);
		}
		else {
			NSMutableString *tmpStr = [NSMutableString string];
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START]) {
				[tmpStr appendFormat:@"Start TC=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START]];
			}
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]) {
				if([tmpStr length]) [tmpStr appendFormat:@"; Duration TC=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]];
				else [tmpStr appendFormat:@"Duration TC=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]];
			}
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]) {
				if([tmpStr length]) [tmpStr appendFormat:@"; Media FPS=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]];
				else [tmpStr appendFormat:@"Media FPS=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]];
			}
			if([tmpStr length]) {
				added = YES;
				atomID[0] = 0xa9;
				memcpy(atomID+1,"cmt",3);
				appendTextTag(tagData, atomID, tmpStr);
			}
		}
		
		/* lyr atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"lyr",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* grp atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP];
			atomID[0] = 0xa9;
			memcpy(atomID+1,"grp",3);
			appendTextTag(tagData, atomID, str);
		}
		
		/* sonm atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT];
			appendTextTag(tagData, "sonm", str);
		}
		
		/* soar atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT];
			appendTextTag(tagData, "soar", str);
		}
		
		/* soal atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT];
			appendTextTag(tagData, "soal", str);
		}
		
		/* soaa atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT];
			appendTextTag(tagData, "soaa", str);
		}
		
		/* soco atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT];
			appendTextTag(tagData, "soco", str);
		}
		
		/* cpil atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
			if([[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION] boolValue]) {
				added = YES;
				appendNumericTag(tagData, "cpil", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION], 1);
			}
		}
		
		/* Gracenote CDDB information */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE]) {
			added = YES;
			appendUserDefinedComment(tagData, @"iTunes_CDDB_IDs", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]) {
			added = YES;
			appendUserDefinedComment(tagData, @"iTunes_CDDB_1", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]);
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
				appendUserDefinedComment(tagData, @"iTunes_CDDB_TrackNumber", [NSString stringWithFormat:@"%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] intValue]]);
			}
		}
		
		/* tmpo atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM]) {
			added = YES;
			appendNumericTag(tagData, "tmpo", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM], 2);
		}
		
		/* cprt atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COPYRIGHT]) {
			added = YES;
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COPYRIGHT];
			appendTextTag(tagData, "cprt", str);
		}
		
		/* pgap atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM]) {
			if([[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM] boolValue]) {
				added = YES;
				appendNumericTag(tagData, "pgap", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM], 1);
			}
		}
		
		/* MusicBrainz related tags */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Track Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Album Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Artist Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Album Artist Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Disc Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicIP PUID", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Album Status", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Album Type", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Album Release Country", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Release Group Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MusicBrainz Work Id", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]);
		}
		
		/* Timecode related tags */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START]) {
			added = YES;
			appendUserDefinedComment(tagData, @"SMPTE_TIMECODE_START", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]) {
			added = YES;
			appendUserDefinedComment(tagData, @"SMPTE_TIMECODE_DURATION", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]) {
			added = YES;
			appendUserDefinedComment(tagData, @"MEDIA_FPS", [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]);
		}
		
		/* covr atom */
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER]) {
			added = YES;
			NSData *imgData = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER];
			tmp = [imgData length]+24;
			tmp = SWAP32(tmp);
			memcpy(atomID,"covr",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			tmp = [imgData length]+16;
			tmp = SWAP32(tmp);
			memcpy(atomID,"data",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			if([imgData length] >= 8 && 0 == memcmp([imgData bytes], "\x89PNG\x0d\x0a\x1a\x0a", 8))
				tmp = 0xe;
			else if([imgData length] >= 2 && 0 == memcmp([imgData bytes], "BM", 2))
				tmp = 0x1b;
			else if([imgData length] >= 3 && 0 == memcmp([imgData bytes], "GIF", 3))
				tmp = 0xc;
			else tmp = 0xd;
			tmp = SWAP32(tmp);
			[tagData appendBytes:&tmp length:4];
			tmp = 0;
			[tagData appendBytes:&tmp length:4];
			[tagData appendData:imgData];
		}
	}
	
	/* version strings */
	long version;
	OSErr result;
	result = Gestalt(gestaltQuickTime,&version);
	if (result == noErr)
	{
		added = YES;
		NSString *str = [NSString stringWithFormat:@"X Lossless Decoder %@, QuickTime %d.%d.%d, %@",[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"],(version>>24)&0xF,(version>>20)&0xF,(version>>16)&0xF,encoderAttr];
		atomID[0] = 0xa9;
		memcpy(atomID+1,"too",3);
		appendTextTag(tagData, atomID, str);
	}
	
	/* gapless information */
	if(addGaplessInfo) {
		added = YES;
		tmp = 0xBC;
		tmp = SWAP32(tmp);
		memcpy(atomID,"----",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		tmp = 0x1C;
		tmp = SWAP32(tmp);
		memcpy(atomID,"mean",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		tmp = 0;
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:"com.apple.iTunes" length:16];
		tmp = 0x14;
		tmp = SWAP32(tmp);
		memcpy(atomID,"name",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		tmp = 0;
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:"iTunSMPB" length:8];
		tmp = 0x84;
		tmp = SWAP32(tmp);
		memcpy(atomID,"data",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		tmp = 1;
		tmp = SWAP32(tmp);
		[tagData appendBytes:&tmp length:4];
		tmp = 0;
		[tagData appendBytes:&tmp length:4];
		
		[tagData appendBytes:" 00000000 00000840 " length:19];
		gaplessDataRange.location = [tagData length];
		gaplessDataRange.length = 25;
		[tagData appendBytes:"00000000 0000000000000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000" length:97];
	}
	if(added) { //bitrate data
		ComponentDescription cd;
		cd.componentType = kAudioEncoderComponentType;
		cd.componentSubType = outputFormat.mFormatID;
		cd.componentManufacturer = kAudioUnitManufacturer_Apple;
		cd.componentFlags = 0;
		cd.componentFlagsMask = 0;
		
		tmp = 0x6F;
		tmp = SWAP32(tmp);
		memcpy(atomID,"----",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		tmp = 0x1C;
		tmp = SWAP32(tmp);
		memcpy(atomID,"mean",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		tmp = 0;
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:"com.apple.iTunes" length:16];
		tmp = 0x1B;
		tmp = SWAP32(tmp);
		memcpy(atomID,"name",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		tmp = 0;
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:"Encoding Params" length:15];
		tmp = 0x30;
		tmp = SWAP32(tmp);
		memcpy(atomID,"data",4);
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:atomID length:4];
		tmp = 0;
		[tagData appendBytes:&tmp length:4];
		[tagData appendBytes:&tmp length:4];
		
		tmp = 1;
		tmp = SWAP32(tmp);
		[tagData appendBytes:"vers" length:4];
		[tagData appendBytes:&tmp length:4];
		
		tmp = [[configurations objectForKey:@"EncodeMode"] unsignedIntValue];
		tmp = SWAP32(tmp);
		[tagData appendBytes:"acbf" length:4];
		[tagData appendBytes:&tmp length:4];
		
		tmp = 0;
		[tagData appendBytes:"brat" length:4];
		bitrateDataRange.location = [tagData length];
		bitrateDataRange.length = 4;
		[tagData appendBytes:&tmp length:4];
		
		tmp = CallComponentVersion((ComponentInstance)FindNextComponent(NULL, &cd));
		tmp = SWAP32(tmp);
		[tagData appendBytes:"cdcv" length:4];
		[tagData appendBytes:&tmp length:4];
	}
	if(added) {
		int freeSize = 2000;
		/* update length of udta atom */
		tmp = [tagData length] + freeSize;
		tmp = SWAP32(tmp);
		[tagData replaceBytesInRange:NSMakeRange(0,4) withBytes:&tmp];
		
		/* update length of meta atom */
		tmp = [tagData length] - 8 + freeSize;
		tmp = SWAP32(tmp);
		[tagData replaceBytesInRange:NSMakeRange(8,4) withBytes:&tmp];
		
		/* update length of ilst atom */
		tmp = [tagData length] - 54;
		tmp = SWAP32(tmp);
		[tagData replaceBytesInRange:NSMakeRange(54,4) withBytes:&tmp];
		
		/* add free atom */
		if(freeSize) {
			tmp = freeSize;
			tmp = SWAP32(tmp);
			memcpy(atomID,"free",4);
			[tagData appendBytes:&tmp length:4];
			[tagData appendBytes:atomID length:4];
			[tagData increaseLengthBy:freeSize-8];
		}
	}
	else [tagData setLength:0];
}

- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track
{
	FSRef dirFSRef;
	FSPathMakeRef((UInt8 *)[[str stringByDeletingLastPathComponent] UTF8String] ,&dirFSRef,NULL);
	
	if([[NSFileManager defaultManager] fileExistsAtPath:str]) {
		if(![[NSFileManager defaultManager] removeFileAtPath:str handler:nil]) return NO;
	}
	if(ExtAudioFileCreateNew(&dirFSRef, (CFStringRef)[str lastPathComponent], kAudioFileM4AType, &outputFormat, NULL, &file) != noErr)
	{
		NSLog(@"ExtAudioFileCreateNew failure");
		file = NULL;
		return NO;
	}
	
	if(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &inputFormat) != noErr) {
		NSLog(@"ExtAudioFileSetProperty kExtAudioFileProperty_ClientDataFormat failure");
		ExtAudioFileDispose(file);
		file = NULL;
		return NO;
	}
	
	AudioConverterRef converter;
	UInt32 size = sizeof(converter);
	if(ExtAudioFileGetProperty(file, kExtAudioFileProperty_AudioConverter, &size, &converter) != noErr) {
		NSLog(@"ExtAudioFileGetProperty kExtAudioFileProperty_AudioConverter failure");
		ExtAudioFileDispose(file);
		file = NULL;
		return NO;
	}
	
	UInt32 bitrate = [[configurations objectForKey:@"Bitrate"] unsignedIntValue];
	UInt32 quality = [[configurations objectForKey:@"Quality"] unsignedIntValue];
	UInt32 mode = [[configurations objectForKey:@"EncodeMode"] unsignedIntValue];
	UInt32 vbrQuality = [[configurations objectForKey:@"VbrQuality"] unsignedIntValue];
	//UInt32 srcQuality = kAudioConverterQuality_Medium;
	
	NSMutableString *encoderAttr = [[[NSMutableString alloc] init] autorelease];
	if(sbrEnabled) [encoderAttr appendString:@"High Efficiency, "];
	switch(mode) {
		case 0:
			[encoderAttr appendString:@"CBR "];
			break;
		case 1:
			[encoderAttr appendString:@"ABR "];
			break;
		case 2:
			[encoderAttr appendString:@"Constrained VBR "];
			break;
		case 3:
			[encoderAttr appendString:@"True VBR "];
			break;
	}
	
	/*if(AudioConverterSetProperty(converter, kAudioConverterSampleRateConverterQuality, sizeof(srcQuality), &srcQuality) != noErr) {
		NSLog(@"AudioConverterSetProperty kAudioConverterSampleRateConverterQuality failure");
		ExtAudioFileDispose(file);
		file = NULL;
		return NO;
	}*/
	if(AudioConverterSetProperty(converter, kAudioConverterCodecQuality, sizeof(quality), &quality) != noErr) {
		NSLog(@"AudioConverterSetProperty kAudioConverterCodecQuality failure");
		ExtAudioFileDispose(file);
		file = NULL;
		return NO;
	}
	if(AudioConverterSetProperty(converter, kAudioCodecBitRateFormat, sizeof(mode), &mode) != noErr) {
		NSLog(@"AudioConverterSetProperty kAudioCodecBitRateFormat failure");
		ExtAudioFileDispose(file);
		file = NULL;
		return NO;
	}
	if(mode != 3) {
		[encoderAttr appendString:[NSString stringWithFormat:@"%d kbps",bitrate/1000]];
		if(AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, sizeof(bitrate), &bitrate) != noErr) {
			NSLog(@"AudioConverterSetProperty kAudioConverterEncodeBitRate failure");
			ExtAudioFileDispose(file);
			file = NULL;
			return NO;
		}
	}
	else {
		[encoderAttr appendString:[NSString stringWithFormat:@"Quality %d",vbrQuality]];
		if(AudioConverterSetProperty(converter, 'vbrq', sizeof(vbrQuality), &vbrQuality) != noErr) {
			NSLog(@"AudioConverterSetProperty vbrq failure");
			ExtAudioFileDispose(file);
			file = NULL;
			return NO;
		}
	}
	
	CFArrayRef converterPropertySettings;
	size = sizeof(converterPropertySettings);
	if(AudioConverterGetProperty(converter, kAudioConverterPropertySettings, &size, &converterPropertySettings) != noErr) {
		NSLog(@"AudioConverterGetProperty kAudioConverterPropertySettings failure");
		ExtAudioFileDispose(file);
		file = NULL;
		return NO;
	}
	if(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ConverterConfig, size, &converterPropertySettings) != noErr) {
		NSLog(@"ExtAudioFileSetProperty kExtAudioFileProperty_ConverterConfig failure");
		ExtAudioFileDispose(file);
		file = NULL;
		return NO;
	}
	/*
	AudioChannelLayout channeLayout;
	channeLayout.mNumberChannelDescriptions = 0;
	switch(format.channels) {
		case 3:
			channeLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_3_0_A;
			break;
		case 4:
			channeLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_4_0_A;
			break;
		case 5:
			channeLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_5_0_A;
			break;
		case 6:
			channeLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_5_1_A;
			break;
		case 7:
			channeLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_6_1_A;
			break;
		case 8:
			channeLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_7_1_A;
			break;
	}
	if(format.channels > 2 && format.channels < 9) {
		if(AudioConverterSetProperty(converter, kAudioConverterInputChannelLayout, sizeof(channeLayout), &channeLayout) != noErr) {
			NSLog(@"AudioConverterSetProperty kAudioConverterInputChannelLayout failure");
			ExtAudioFileDispose(file);
			file = NULL;
			return NO;
		}
	}
	*/
	path = [str retain];
	addGaplessInfo = [[configurations objectForKey:@"AddGaplessInfo"] boolValue];
	if([configurations objectForKey:@"EmbedChapter"])
		embedChapter = [[configurations objectForKey:@"EmbedChapter"] boolValue];
	
	/* construct tag data */
	if(addTag || addGaplessInfo) {
		[self setupTagDataWithTrack:track andEncoderAttr:encoderAttr];
	}
	/* construct chapter data */
	if(embedChapter && [[track metadata] objectForKey:XLD_METADATA_TRACKLIST] && [[track metadata] objectForKey:XLD_METADATA_TOTALSAMPLES]) {
		NSData *chapterTrack = buildChapterTrack([[[track metadata] objectForKey:XLD_METADATA_TOTALSAMPLES] unsignedIntValue], format.samplerate, [[track metadata] objectForKey:XLD_METADATA_TRACKLIST]);
		chapterMdat = [buildChapterData([[track metadata] objectForKey:XLD_METADATA_TRACKLIST]) retain];
		[tagData replaceBytesInRange:NSMakeRange(0, 0) withBytes:[chapterTrack bytes] length:[chapterTrack length]];
		if(gaplessDataRange.location) gaplessDataRange.location += [chapterTrack length];
		if(bitrateDataRange.location) bitrateDataRange.location += [chapterTrack length];
	}
	
	totalFrames = 0;
	return YES;
}

- (NSString *)extensionStr
{
	return @"m4a";
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	fillBufList.mNumberBuffers = 1;
	fillBufList.mBuffers[0].mNumberChannels = format.channels;
	fillBufList.mBuffers[0].mDataByteSize = counts*4*format.channels;
	fillBufList.mBuffers[0].mData = buffer;
	/*if(format.isFloat && (format.channels > 2)) {
		int i;
		float *buf_p = (float *)buffer;
		for(i=0;i<counts*format.channels;i++) {
			buffer[i] = (int)round(buf_p[i]*2147483647);
		}
	}*/
	
	if(ExtAudioFileWrite(file, counts, &fillBufList) != noErr) {
		return NO;
	}
	
	totalFrames += counts;
	
	return YES;
}

- (void)optimizeAtoms
{
	int tmp;
	int moovSize;
	off_t origSize;
	char atom[4];
	struct stat stbuf;
	
	stat([path UTF8String], &stbuf);
	origSize = stbuf.st_size;
	
	FILE *fp = fopen([path UTF8String], "r+b");
	if(!fp) return;
	
	if(floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_4) fcntl(fileno(fp), F_NOCACHE, 1);
	
	int bufferSize = 1024*1024;
	char *tmpbuf = (char *)malloc(bufferSize);
	char *tmpbuf2 = (char *)malloc(bufferSize);
	char *read = tmpbuf;
	char *write = tmpbuf2;
	char *swap;
	char *moovbuf = NULL;
	int i;
	BOOL moov_after_mdat = NO;
	
	while(1) { //skip until moov;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"moov",4)) break;
		if(!memcmp(atom,"mdat",4)) moov_after_mdat = YES;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	if(!moov_after_mdat) goto end;
	
	off_t pos_moov = ftello(fp) - 8;
	moovSize = origSize - pos_moov;
	
	while(1) { //skip until trak;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"trak",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until mdia;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"mdia",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until minf;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"minf",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until stbl;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"stbl",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until stco;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"stco",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	int *stco = (int *)malloc(tmp-8);
	if(fread(stco,1,tmp-8,fp) < tmp-8) goto end;
	int nElement = SWAP32(stco[1]);
	
	/* update stco atom */
	
	for(i=0;i<nElement;i++) {
		stco[2+i] = SWAP32(SWAP32(stco[2+i])+moovSize);
	}
	if(fseeko(fp,8-tmp,SEEK_CUR) != 0) goto end;
	if(fwrite(stco,1,tmp-8,fp) < tmp-8) goto end;
	
	free(stco);
	
	rewind(fp);
	
	/* save moov atom */
	
	moovbuf = (char *)malloc(moovSize);
	if(fseeko(fp,pos_moov,SEEK_SET) != 0) goto end;
	if(fread(moovbuf,1,moovSize,fp) < moovSize) goto end;
	rewind(fp);
	
	while(1) { //skip until ftyp;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"ftyp",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	/* position after ftyp atom is the inserting point */
	if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	pos_moov = ftello(fp);
	
	/* optimize */
	
	long long bytesToMove = origSize-pos_moov-moovSize;
	
	if(bytesToMove < moovSize) {
		if(bufferSize < bytesToMove) {
			tmpbuf = (char *)realloc(tmpbuf,bytesToMove);
			read = tmpbuf;
		}
		if(fread(read,1,bytesToMove,fp) < bytesToMove) goto end;
		if(fseeko(fp,moovSize-bytesToMove,SEEK_CUR) != 0) goto end;
		if(fwrite(read,1,bytesToMove,fp) < bytesToMove) goto end;
	}
	else if(bytesToMove > bufferSize) {
		if(bufferSize < moovSize) {
			tmpbuf = (char *)realloc(tmpbuf,moovSize);
			tmpbuf2 = (char *)realloc(tmpbuf2,moovSize);
			read = tmpbuf;
			write = tmpbuf2;
			bufferSize = moovSize;
			if(bytesToMove <= bufferSize) goto moveBlock_is_smaller_than_buffer;
		}
		if(fread(write,1,bufferSize,fp) < bufferSize) goto end;
		bytesToMove -= bufferSize;
		while(bytesToMove > bufferSize) {
			if(fread(read,1,bufferSize,fp) < bufferSize) goto end;
			if(fseeko(fp,moovSize-2*bufferSize,SEEK_CUR) != 0) goto end;
			if(fwrite(write,1,bufferSize,fp) < bufferSize) goto end;
			if(fseeko(fp,bufferSize-moovSize,SEEK_CUR) != 0) goto end;
			swap = read;
			read = write;
			write = swap;
			bytesToMove -= bufferSize;
			//NSLog(@"DEBUG: %d bytes left",bytesToMove);
		}
		if(fread(read,1,bytesToMove,fp) < bytesToMove) goto end;
		if(fseeko(fp,moovSize-bufferSize-bytesToMove,SEEK_CUR) != 0) goto end;
		if(fwrite(write,1,bufferSize,fp) < bufferSize) goto end;
		if(fwrite(read,1,bytesToMove,fp) < bytesToMove) goto end;
	}
	else {
moveBlock_is_smaller_than_buffer:
		if(fread(read,1,bytesToMove,fp) < bytesToMove) goto end;
		if(moovSize < bytesToMove) {
			if(fseeko(fp,moovSize-bytesToMove,SEEK_CUR) != 0) goto end;
		}
		else {
			if(fseeko(fp,0-bytesToMove,SEEK_CUR) != 0) goto end;
			if(fwrite(moovbuf,1,moovSize,fp) < moovSize) goto end;
		}
		if(fwrite(read,1,bytesToMove,fp) < bytesToMove) goto end;
	}
	
	if(fseeko(fp,pos_moov,SEEK_SET) != 0) goto end;
	if(fwrite(moovbuf,1,moovSize,fp) < moovSize) goto end;
	
end:
	if(moovbuf) free(moovbuf);
	free(tmpbuf);
	free(tmpbuf2);
	fclose(fp);
}

- (void)appendChapterData
{
	if(!chapterMdat) return;
	
	FILE *fp = fopen([path UTF8String], "r+b");
	if(!fp) return;
	int i;
	int tmp;
	char atom[4];
	int *stco = NULL;
	struct stat stbuf;
	stat([path UTF8String], &stbuf);
	
	if(floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_4) fcntl(fileno(fp), F_NOCACHE, 1);
	
	/* write mdat at the end of file */
	if(fseeko(fp,0,SEEK_END) != 0) goto end;
	fwrite([chapterMdat bytes],1,[chapterMdat length],fp);
	
	/* find text track (ID=2) and its stco */
	if(fseeko(fp,0,SEEK_SET) != 0) goto end;
	while(1) { //skip until moov;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"moov",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until trak;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"trak",4)) {
			if(fseeko(fp,20,SEEK_CUR) != 0) goto end;
			int trackID;
			if(fread(&trackID,4,1,fp) < 1) goto end;
			trackID = NSSwapBigIntToHost(trackID);
			if(trackID == 1) { // audio track; increase length by 20 bytes because tref is appended
				if(fseeko(fp,-32,SEEK_CUR) != 0) goto end;
				int updatedLength = tmp + 20;
				updatedLength = NSSwapHostIntToBig(updatedLength);
				if(fwrite(&updatedLength,4,1,fp) < 1) goto end;
				if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
			}
			else if(trackID == 2) {
				if(fseeko(fp,-24,SEEK_CUR) != 0) goto end;
				break;
			}
			else if(fseeko(fp,-24,SEEK_CUR) != 0) goto end;
		}
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until mdia;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"mdia",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until minf;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"minf",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until stbl;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"stbl",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until stco;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"stco",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	stco = (int *)malloc(tmp-8);
	if(fread(stco,1,tmp-8,fp) < tmp-8) goto end;
	int nElement = NSSwapBigIntToHost(stco[1]);
	
	/* update stco atom */
	for(i=0;i<nElement;i++) {
		unsigned int newOffset = NSSwapBigIntToHost(stco[2+i])+stbuf.st_size;
		stco[2+i] = NSSwapHostIntToBig(newOffset);
	}
	if(fseeko(fp,8-tmp,SEEK_CUR) != 0) goto end;
	if(fwrite(stco,1,tmp-8,fp) < tmp-8) goto end;
	
end:
	if(stco) free(stco);
	fclose(fp);
}

- (void)finalize
{
	if(file) ExtAudioFileDispose(file);
	file = NULL;
	if((addTag || addGaplessInfo) && [tagData length]) {
		//NSLog(@"DEBUG: ExtAudioFileDispose success");
		int tmp;
		int udtaSize = [tagData length];
		off_t origSize;
		char atom[4];
		struct stat stbuf;
		
		stat([path UTF8String], &stbuf);
		origSize = stbuf.st_size;
		
		FILE *fp = fopen([path UTF8String], "r+b");
		if(!fp) return;
		//NSLog(@"DEBUG: fopen success");
		
		if(floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_4) fcntl(fileno(fp), F_NOCACHE, 1);
		
		int bufferSize = 1024*1024;
		char *tmpbuf = (char *)malloc(bufferSize);
		char *tmpbuf2 = (char *)malloc(bufferSize);
		char *read = tmpbuf;
		char *write = tmpbuf2;
		char *swap;
		BOOL moov_after_mdat = NO;
		unsigned int bitrate = [[configurations objectForKey:@"BitrateToWrite"] unsignedIntValue];
		int i;
		
		if(!bitrate) {
			while(1) { //skip until mdat;
				if(fread(&tmp,4,1,fp) < 1) goto end;
				if(fread(atom,1,4,fp) < 4) goto end;
				tmp = SWAP32(tmp);
				if(!memcmp(atom,"mdat",4)) break;
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			double sec = (double)totalFrames/(double)format.samplerate;
			bitrate = round((tmp-8)/sec*8) ;
			rewind(fp);
		}
		//NSLog(@"%d",bitrate);
		
		tmp = SWAP32(bitrate);
		if(bitrateDataRange.location != 0) [tagData replaceBytesInRange:bitrateDataRange withBytes:&tmp];
		if(addGaplessInfo) {
			int actualFreq = getM4aFrequency(fp);
			if((actualFreq && (actualFreq != format.samplerate))) totalFrames = (int)round((double)totalFrames*actualFreq/format.samplerate);
			else if(sbrEnabled) {
				if(actualFreq) totalFrames = (int)round((double)totalFrames*(actualFreq/2)/format.samplerate);
				else totalFrames = (totalFrames >> 1) + (totalFrames & 1);
			}
			int padding = (int)ceil((totalFrames + 2112)/1024.0)*1024 - (totalFrames + 2112);
			[tagData replaceBytesInRange:gaplessDataRange withBytes:[[NSString stringWithFormat:@"%08X %016llX",padding,totalFrames] UTF8String]];
		}
		
		while(1) { //skip until moov;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"moov",4)) break;
			if(!memcmp(atom,"mdat",4)) moov_after_mdat = YES;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		if(fseeko(fp,-8,SEEK_CUR) != 0) goto end;
		
		/* update moov atom size */
		if(fread(&tmp,4,1,fp) < 1) goto end;
		int moovSize = SWAP32(tmp);
		if(fseeko(fp,-4,SEEK_CUR) != 0) goto end;
		tmp = moovSize + udtaSize;
		tmp = SWAP32(tmp);
		if(fwrite(&tmp,4,1,fp) < 1) goto end;
		
		off_t pos_moov = ftello(fp);
		
		//NSLog(@"DEBUG: seeking to stco atom...");
		
		if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
		
		int rest = moovSize - 8;
		while(rest > 0) { //skip until udta; find existing udta
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"udta",4)) {
				/*updateUdta(fp, tagData);
				udtaSize = [tagData length];*/
				if((udtaSize >= tmp) && ((ftello(fp)+tmp-8) == (pos_moov+moovSize-4))) {
					if(fseeko(fp,-8,SEEK_CUR) != 0) goto end;
					if(fwrite([tagData bytes],1,tmp,fp) < tmp) goto end;
					[tagData replaceBytesInRange:NSMakeRange(0,tmp) withBytes:NULL length:0];
					udtaSize = [tagData length];
					if(fseeko(fp,pos_moov-4,SEEK_SET) != 0) goto end;
					tmp = moovSize + udtaSize;
					tmp = SWAP32(tmp);
					if(fwrite(&tmp,4,1,fp) < 1) goto end;
				}
				else {
					char tmp2 = 0;
					if(fseeko(fp,-4,SEEK_CUR) != 0) goto end;
					if(fwrite("free",1,4,fp) < 4) goto end;
					for(i=0;i<tmp-8;i++) {
						if(fwrite(&tmp2,1,1,fp) < 1) goto end;
					}
				}
				break;
			}
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			rest -= tmp;
		}
		
		if(fseeko(fp,pos_moov+4,SEEK_SET) != 0) goto end;
		
		while(1) { //skip until trak;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"trak",4)) break;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		/*if(moov_after_mdat) {
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			goto beginWrite;
		}*/
		
		while(1) { //skip until mdia;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"mdia",4)) break;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		while(1) { //skip until minf;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"minf",4)) break;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		while(1) { //skip until stbl;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"stbl",4)) break;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		//if([delegate writeAccurateBitrate]) {
			off_t nextAtom = ftello(fp);
			while(1) { //skip until esds;
				if(fread(atom,1,4,fp) < 4) goto end;
				if(!memcmp(atom,"esds",4)) break;
				if(fseeko(fp,-3,SEEK_CUR) != 0) goto end;
			}
			
			if(fseeko(fp,5,SEEK_CUR) != 0) goto end;
			for(i=0;i<3;i++) {
				if(fread(atom,1,1,fp) < 1) goto end;
				if((unsigned char)atom[0] != 0x80) {
					if(fseeko(fp,-1,SEEK_CUR) != 0) goto end;
					break;
				}
			}
			if(fseeko(fp,5,SEEK_CUR) != 0) goto end;
			for(i=0;i<3;i++) {
				if(fread(atom,1,1,fp) < 1) goto end;
				if((unsigned char)atom[0] != 0x80) {
					if(fseeko(fp,-1,SEEK_CUR) != 0) goto end;
					break;
				}
			}
			if(fseeko(fp,10,SEEK_CUR) != 0) goto end;
			tmp = SWAP32(bitrate);
			if(fwrite(&tmp,4,1,fp) < 1) goto end;
			
			if(!udtaSize) goto end;
			if(moov_after_mdat) {
				goto beginWrite;
			}
			else {
				if(fseeko(fp,nextAtom,SEEK_SET) != 0) goto end;
			}
		//}
		
		while(1) { //skip until stco;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			tmp = SWAP32(tmp);
			if(!memcmp(atom,"stco",4)) break;
			if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
		}
		
		int *stco = (int *)malloc(tmp-8);
		if(fread(stco,1,tmp-8,fp) < tmp-8) goto end;
		int nElement = SWAP32(stco[1]);
		
		//NSLog(@"DEBUG: updating stco atom...");
		
		/* update stco atom */
		
		for(i=0;i<nElement;i++) {
			stco[2+i] = SWAP32(SWAP32(stco[2+i])+udtaSize);
		}
		if(fseeko(fp,8-tmp,SEEK_CUR) != 0) goto end;
		if(fwrite(stco,1,tmp-8,fp) < tmp-8) goto end;
		
		free(stco);
		
		//NSLog(@"DEBUG: now moving blocks...");
		
		/* write tags */
beginWrite:
		if(fseeko(fp,pos_moov,SEEK_SET) != 0) goto end;
		if(fseeko(fp,moovSize-4,SEEK_CUR) != 0) goto end;
		off_t pos_tag = ftello(fp);
		
		//if(fseek(fp,0-udtaSize,SEEK_END) != 0) goto end;
		
		long long bytesToMove = origSize-pos_tag;
		if(bytesToMove == 0) goto write;
		
		if(bytesToMove < udtaSize) {
			if(bufferSize < udtaSize) {
				tmpbuf = (char *)realloc(tmpbuf,udtaSize);
				read = tmpbuf;
			}
			if(fread(read,1,bytesToMove,fp) < bytesToMove) goto end;
			if(fwrite(read,1,udtaSize-bytesToMove,fp) < udtaSize-bytesToMove) goto end;
			if(fwrite(read,1,bytesToMove,fp) < bytesToMove) goto end;
		}
		else if(bytesToMove > bufferSize) {
			if(bufferSize < udtaSize) {
				tmpbuf = (char *)realloc(tmpbuf,udtaSize);
				tmpbuf2 = (char *)realloc(tmpbuf2,udtaSize);
				read = tmpbuf;
				write = tmpbuf2;
				bufferSize = udtaSize;
				if(bytesToMove <= bufferSize) goto moveBlock_is_smaller_than_buffer;
			}
			if(fread(write,1,bufferSize,fp) < bufferSize) goto end;
			bytesToMove -= bufferSize;
			while(bytesToMove > bufferSize) {
				if(fread(read,1,bufferSize,fp) < bufferSize) goto end;
				if(fseeko(fp,udtaSize-2*bufferSize,SEEK_CUR) != 0) goto end;
				if(fwrite(write,1,bufferSize,fp) < bufferSize) goto end;
				if(fseeko(fp,bufferSize-udtaSize,SEEK_CUR) != 0) goto end;
				swap = read;
				read = write;
				write = swap;
				bytesToMove -= bufferSize;
				//NSLog(@"DEBUG: %d bytes left",bytesToMove);
			}
			if(fread(read,1,bytesToMove,fp) < bytesToMove) goto end;
			if(fseeko(fp,udtaSize-bufferSize-bytesToMove,SEEK_CUR) != 0) goto end;
			if(fwrite(write,1,bufferSize,fp) < bufferSize) goto end;
			if(fwrite(read,1,bytesToMove,fp) < bytesToMove) goto end;
		}
		else {
moveBlock_is_smaller_than_buffer:
			if(fread(read,1,bytesToMove,fp) < bytesToMove) goto end;
			if(udtaSize < bytesToMove) {
				if(fseeko(fp,udtaSize-bytesToMove,SEEK_CUR) != 0) goto end;
			}
			else {
				if(fseeko(fp,0-bytesToMove,SEEK_CUR) != 0) goto end;
				if(fwrite([tagData bytes],1,udtaSize,fp) < udtaSize) goto end;
			}
			if(fwrite(read,1,bytesToMove,fp) < bytesToMove) goto end;
		}
		
		if(fseeko(fp,pos_tag,SEEK_SET) != 0) goto end;
write:
		if(fwrite([tagData bytes],1,udtaSize,fp) < udtaSize) goto end;
		
		//NSLog(@"DEBUG: tag writing successful");
end:
		free(tmpbuf);
		free(tmpbuf2);
		fclose(fp);
	}
	[self optimizeAtoms];
	if(embedChapter) [self appendChapterData];
}

- (void)closeFile
{
	if(file) ExtAudioFileDispose(file);
	file = NULL;
	if(path) [path release];
	path = nil;
	[tagData setLength:0];
	totalFrames = 0;
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}

@end
