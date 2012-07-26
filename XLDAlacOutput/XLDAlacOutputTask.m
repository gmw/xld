//
//  XLDAlacOutputTask.m
//  XLDAlacOutput
//
//  Created by tmkk on 06/09/08.
//  Copyright 2006 tmkk. All rights reserved.
//

#import "XLDAlacOutputTask.h"
#import "XLDAlacOutput.h"

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

static void updateM4aFileDurations(FILE *fp, int freq, xldoffset_t total)
{
	char atom[4];
	int tmp;
	off_t initPos = ftello(fp);
	off_t back;
	int timescale_moov;
	
	if(fseeko(fp,0,SEEK_SET) != 0) goto end;
	
	while(1) { //skip until moov;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"moov",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	back = ftello(fp);
	while(1) { //skip until mvhd;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"mvhd",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	if(fseeko(fp,12,SEEK_CUR) != 0) goto end;
	if(fread(&tmp,4,1,fp) < 1) goto end;
	timescale_moov = SWAP32(tmp);
	if(timescale_moov == freq) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		tmp = SWAP32(tmp);
		if(tmp != total);
		tmp = total;
		tmp = SWAP32(tmp);
		if(fseeko(fp,-4,SEEK_CUR) != 0) goto end;
		if(fwrite(&tmp,4,1,fp) < 1) goto end;
	}
	if(fseeko(fp,back,SEEK_SET) != 0) goto end;
	
	while(1) { //skip until trak;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"trak",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	back = ftello(fp);
	while(1) { //skip until tkhd;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"tkhd",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	if(fseeko(fp,20,SEEK_CUR) != 0) goto end;
	if(timescale_moov == freq) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		tmp = SWAP32(tmp);
		if(tmp != total);
		tmp = total;
		tmp = SWAP32(tmp);
		if(fseeko(fp,-4,SEEK_CUR) != 0) goto end;
		if(fwrite(&tmp,4,1,fp) < 1) goto end;
	}
	if(fseeko(fp,back,SEEK_SET) != 0) goto end;
	
	while(1) { //skip until mdia;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"mdia",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until mdhd;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"mdhd",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	if(fseeko(fp,12,SEEK_CUR) != 0) goto end;
	if(fread(&tmp,4,1,fp) < 1) goto end;
	tmp = SWAP32(tmp);
	if(tmp == freq) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		tmp = SWAP32(tmp);
		if(tmp != total);
		tmp = total;
		tmp = SWAP32(tmp);
		if(fseeko(fp,-4,SEEK_CUR) != 0) goto end;
		if(fwrite(&tmp,4,1,fp) < 1) goto end;
	}
	
end:
	fseeko(fp,initPos,SEEK_SET);
}

static int updateM4aFileInfo(FILE *fp)
{
	char atom[4];
	int tmp,tmp2,tmp3,tmp4,i,j,k,n,m;
	off_t initPos = ftello(fp);
	int freq,frequency = 0;
	short bits;
	char chan;
	xldoffset_t totalSamples = 0;
	int totalALACFrames = 0;
	int *ALACFrameSizeTable = NULL;
	int *ALACFrameToChunkTable = NULL;
	unsigned int *chunkIndexTable = NULL;
	int lastChunkStartALACFrame = 1;
	int lastALACFrameSampleCount = 0;
	
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
	
	off_t stblPos = ftello(fp);
	
	while(1) { //skip until alac;
		if(fread(atom,1,4,fp) < 4) goto end;
		if(!memcmp(atom,"alac",4)) break;
		if(fseeko(fp,-3,SEEK_CUR) != 0) goto end;
	}
	
	off_t alacPos = ftello(fp);
	
	if(fseeko(fp,0x1c,SEEK_CUR) != 0) goto end;
	if(fread(&tmp,4,1,fp) < 1) goto end;
	tmp = SWAP32(tmp);
	if(tmp != 0x24) goto end;
	if(fread(atom,1,4,fp) < 4) goto end;
	if(memcmp(atom,"alac",4)) goto end;
	
	if(fseeko(fp,8,SEEK_CUR) != 0) goto end;
	if(fread(&bits,2,1,fp) < 1) goto end;
	if(fseeko(fp,3,SEEK_CUR) != 0) goto end;
	if(fread(&chan,1,1,fp) < 1) goto end;
	if(fseeko(fp,10,SEEK_CUR) != 0) goto end;
	if(fread(&freq,4,1,fp) < 1) goto end;
	frequency = SWAP32(freq);
	
	if(fseeko(fp,alacPos+17,SEEK_SET) != 0) goto end;
	if(fwrite(&chan,1,1,fp) < 1) goto end;
	if(fwrite(&bits,2,1,fp) < 1) goto end;
	if(frequency <= 65535) {
		/*
		 why? because ISO defined stsd doesn't accept freq above 65535 (unsigned 16bit limit)
		 this field should be ignored by correct inplementation, but unfortunately some decoders refers.
		 class AudioSampleEntry(codingname) extends SampleEntry (codingname){
			 const unsigned int(32)[2] reserved = 0;
			 template unsigned int(16) channelcount = 2;
			 template unsigned int(16) samplesize = 16;
			 unsigned int(16) pre_defined = 0;
			 const unsigned int(16) reserved = 0 ;
			 template unsigned int(32) samplerate = { default samplerate of media}<<16;
		 }
		*/
		freq = frequency << 16;
		freq = SWAP32(freq);
		if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
		if(fwrite(&freq,4,1,fp) < 1) goto end;
	}
	
	if(fseeko(fp,stblPos,SEEK_SET) != 0) goto end;
	
	//fprintf(stderr,"analyzing\n");
	
	while(1) { //skip until stts;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"stts",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
	if(fread(&n,4,1,fp) < 1) goto end;
	n = SWAP32(n);
	m=0;
	for(i=0;i<n;i++) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(&tmp2,4,1,fp) < 1) goto end;
		tmp = SWAP32(tmp);
		tmp2 = SWAP32(tmp2);
		totalSamples += tmp * tmp2;
		m += tmp;
		lastALACFrameSampleCount = tmp2;
	}
	
	//fprintf(stderr,"totalSamples: %lld\n",totalSamples);
	//fprintf(stderr,"lastALACFrameSampleCount: %d\n",lastALACFrameSampleCount);
	
	if(lastALACFrameSampleCount == 0) goto end;
	
	if(fseeko(fp,stblPos,SEEK_SET) != 0) goto end;
	
	while(1) { //skip until stsz;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"stsz",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	if(fseeko(fp,8,SEEK_CUR) != 0) goto end;
	if(fread(&tmp,4,1,fp) < 1) goto end;
	totalALACFrames = SWAP32(tmp);
	if(totalALACFrames != m) goto end;
	ALACFrameSizeTable = (int *)calloc(totalALACFrames,sizeof(int));
	ALACFrameToChunkTable = (int *)malloc(totalALACFrames*sizeof(int));
	memset(ALACFrameToChunkTable, -1, totalALACFrames*sizeof(int));
	for(i=0;i<totalALACFrames;i++) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		ALACFrameSizeTable[i] = SWAP32(tmp);
	}
	
	//fprintf(stderr,"totalALACFrames: %d\n",totalALACFrames);
	
	if(fseeko(fp,stblPos,SEEK_SET) != 0) goto end;
	
	while(1) { //skip until stsc;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"stsc",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
	if(fread(&n,4,1,fp) < 1) goto end;
	n = SWAP32(n);
	m=0;
	tmp = -1;
	tmp3 = 0;
	tmp4 = 0;
	for(i=0;i<n&&m<totalALACFrames;i++) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(&tmp2,4,1,fp) < 1) goto end;
		if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
		tmp = SWAP32(tmp);
		tmp2 = SWAP32(tmp2);
		if(tmp3 && tmp3+1 != tmp) {
			for(j=tmp3;j<tmp-1&&m<totalALACFrames;j++) {
				lastChunkStartALACFrame = m+1;
				for(k=0;k<tmp4;k++) {
					ALACFrameToChunkTable[m++] = j+1;
					if(m>=totalALACFrames) break;
				}
			}
		}
		if(m>=totalALACFrames) break;
		lastChunkStartALACFrame = m+1;
		for(j=0;j<tmp2;j++) {
			ALACFrameToChunkTable[m++] = tmp;
			if(m>=totalALACFrames) break;
		}
		tmp3 = tmp;
		tmp4 = tmp2;
	}
	if(tmp3) {
		for(j=tmp3;m<totalALACFrames;j++) {
			lastChunkStartALACFrame = m+1;
			for(k=0;k<tmp4;k++) {
				ALACFrameToChunkTable[m++] = j+1;
				if(m>=totalALACFrames) break;
			}
		}
	}
	
	//fprintf(stderr,"lastChunkStartALACFrame: %d\n",lastChunkStartALACFrame);
	
	if(fseeko(fp,stblPos,SEEK_SET) != 0) goto end;
	
	while(1) { //skip until stco;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"stco",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
	if(fread(&n,4,1,fp) < 1) goto end;
	n = SWAP32(n);
	chunkIndexTable = (unsigned int *)calloc(n,sizeof(unsigned int));
	for(i=0;i<n;i++) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		chunkIndexTable[i] = SWAP32(tmp);
	}
	
	if(ALACFrameToChunkTable[totalALACFrames-1] == -1) goto end;
	if(ALACFrameToChunkTable[totalALACFrames-1] > n) goto end;
	off_t lastFramePos = chunkIndexTable[ALACFrameToChunkTable[totalALACFrames-1]-1];
	for(i=lastChunkStartALACFrame-1;i<totalALACFrames-1;i++) {
		lastFramePos += ALACFrameSizeTable[i];
	}
	if(fseeko(fp,lastFramePos,SEEK_SET) != 0) goto end;
	
	//fprintf(stderr,"chunk index: %d\n",ALACFrameToChunkTable[totalALACFrames-1]);
	//fprintf(stderr,"chunk index table value: %x\n",chunkIndexTable[ALACFrameToChunkTable[totalALACFrames-1]-1]);
	//fprintf(stderr,"chank start position: %llx\n",lastFramePos);
	
	/* analyze last ALAC frame... */
	if(fseek(fp,2,SEEK_CUR) != 0) goto end;
	if(fread(&chan,1,1,fp) < 1) goto end;
	//fprintf(stderr,"has size:%d,verbatim:%d\n",chan & 0x10, chan & 0x02);
	if(chan & 0x10) {
		n = ((unsigned int)chan) << 31;
		if(fread(&chan,1,1,fp) < 1) goto end;
		n |= ((unsigned int)chan) << 23;
		if(fread(&chan,1,1,fp) < 1) goto end;
		n |= ((unsigned int)chan) << 15;
		if(fread(&chan,1,1,fp) < 1) goto end;
		n |= ((unsigned int)chan) << 7;
		if(fread(&chan,1,1,fp) < 1) goto end;
		n |= ((unsigned int)chan) >> 1;
		//fprintf(stderr,"frame size: %d\n",n);
		if(n==0) {
			if(fseeko(fp,stblPos,SEEK_SET) != 0) goto end;
			
			while(1) { //skip until stts;
				if(fread(&tmp,4,1,fp) < 1) goto end;
				if(fread(atom,1,4,fp) < 4) goto end;
				tmp = SWAP32(tmp);
				if(!memcmp(atom,"stts",4)) break;
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			
			if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
			if(fread(&n,4,1,fp) < 1) goto end;
			n = SWAP32(n);
			if(n>1) if(fseeko(fp,(n-1)*8,SEEK_CUR) != 0) goto end;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			tmp = SWAP32(tmp);
			tmp--;
			tmp = SWAP32(tmp);
			if(fseeko(fp,-4,SEEK_CUR) != 0) goto end;
			if(fwrite(&tmp,4,1,fp) < 1) goto end;
			
			totalSamples -= lastALACFrameSampleCount;
			updateM4aFileDurations(fp,frequency,totalSamples);
		}
	}
	
end:
	fseeko(fp,initPos,SEEK_SET);
	if(ALACFrameSizeTable) free(ALACFrameSizeTable);
	if(ALACFrameToChunkTable) free(ALACFrameToChunkTable);
	if(chunkIndexTable) free(chunkIndexTable);
	return frequency;
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

#if 0
static void updateUdta(FILE *fp, NSMutableData *udta)
{
	off_t origPos = ftello(fp);
	int tmp;
	char atom[4];
	NSMutableData *newData = [NSMutableData data];
	void *buf = NULL;
	
	if(fseeko(fp,12,SEEK_CUR) != 0) goto end; //skip until hdlr;
	
	while(1) { //skip until ilst;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = SWAP32(tmp);
		if(!memcmp(atom,"ilst",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	buf = malloc(tmp-8);
	if(fread(buf,1,tmp-8,fp) < tmp-8) goto end;
	
	NSData *dat = [NSData dataWithBytesNoCopy:buf length:tmp-8];
	
	int len = [dat length];
	int current = 0;
	int atomLength;
	int flag;
	while(current < len) {
		[dat getBytes:&atomLength range:NSMakeRange(current,4)];
		[dat getBytes:atom range:NSMakeRange(current+4,4)];
		atomLength = SWAP32(atomLength);
		
		if(!memcmp("----",atom,4)) {
			int offset = 0;
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			tmp = SWAP32(tmp);
			if(tmp <= 12) goto last;
			NSString *meanStr = [[[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+20,tmp-12)] encoding:NSUTF8StringEncoding] autorelease];
			if(!meanStr || ![meanStr isEqualToString:@"com.apple.iTunes"]) goto last;
			offset = tmp;
			
			[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
			tmp = SWAP32(tmp);
			if(tmp <= 12) goto last;
			NSString *nameStr = [[[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+20,tmp-12)] encoding:NSUTF8StringEncoding] autorelease];
			if(!nameStr) goto last;
			offset += tmp;
			
			if([nameStr isEqualToString:@"iTunNORM"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = SWAP32(tmp);
				flag = SWAP32(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				appendUserDefinedComment(newData, @"iTunNORM", str);
			}
		}
	last:
		current += atomLength;
	}
	
	if([newData length]) {
		/* remove padding */
		[udta setLength:[udta length] - 2000];
		
		/* append data */
		[udta appendData:newData];
		
		int freeSize = 2000 - [newData length];
		/* update length of udta atom */
		tmp = [udta length] + freeSize;
		tmp = SWAP32(tmp);
		[udta replaceBytesInRange:NSMakeRange(0,4) withBytes:&tmp];
		
		/* update length of meta atom */
		tmp = [udta length] - 8 + freeSize;
		tmp = SWAP32(tmp);
		[udta replaceBytesInRange:NSMakeRange(8,4) withBytes:&tmp];
		
		/* update length of ilst atom */
		tmp = [udta length] - 54;
		tmp = SWAP32(tmp);
		[udta replaceBytesInRange:NSMakeRange(54,4) withBytes:&tmp];
		
		/* add free atom */
		if(freeSize) {
			tmp = freeSize;
			tmp = SWAP32(tmp);
			[udta appendBytes:&tmp length:4];
			[udta appendBytes:"free" length:4];
			[udta increaseLengthBy:freeSize-8];
		}
	}
	
end:
	fseeko(fp, origPos, SEEK_SET);
}
#endif

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

@implementation XLDAlacOutputTask

- (id)init
{
	[super init];
	tagData = [[NSMutableData alloc] init];
	encodebuf = malloc(8192*4*2);
	encodebufSize = 8192*4*2;
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
	free(encodebuf);
	[tagData release];
	if(chapterMdat) [chapterMdat release];
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	format = fmt;
	
	if(![configurations objectForKey:@"BitDepth"] || ([configurations objectForKey:@"BitDepth"] && [[configurations objectForKey:@"BitDepth"] intValue])) {
		if(format.bps < 2 || format.bps > 4) return NO;
	}
	if(format.isFloat) return NO;
	
	inputFormat.mSampleRate = (Float64)format.samplerate;
	inputFormat.mFormatID = kAudioFormatLinearPCM;
	
#ifdef _BIG_ENDIAN
	inputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsPacked;
#else
	inputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
#endif
	inputFormat.mFramesPerPacket = 1;
	inputFormat.mBytesPerFrame = format.bps * format.channels;
	inputFormat.mBytesPerPacket = inputFormat.mBytesPerFrame;
	inputFormat.mChannelsPerFrame =  format.channels;
	inputFormat.mBitsPerChannel = format.bps*8;
	
	memset(&outputFormat,0,sizeof(AudioStreamBasicDescription));
	
	outputFormat.mFormatID = kAudioFormatAppleLossless;
	if([configurations objectForKey:@"BitDepth"] && [[configurations objectForKey:@"BitDepth"] intValue]) {
		outputFormat.mBitsPerChannel = [[configurations objectForKey:@"BitDepth"] intValue];
	}
	else {
		outputFormat.mBitsPerChannel = format.bps*8;
	}
	switch(outputFormat.mBitsPerChannel) {
		case 16:
			outputFormat.mFormatFlags = 1;
			break;
		case 24:
			outputFormat.mFormatFlags = 3;
			break;
		case 32:
			outputFormat.mFormatFlags = 4;
			break;
	}
	if([[configurations objectForKey:@"Samplerate"] intValue])
		outputFormat.mSampleRate = [[configurations objectForKey:@"Samplerate"] intValue];
	else
		outputFormat.mSampleRate = format.samplerate;
	outputFormat.mChannelsPerFrame = format.channels;
	return YES;
}

- (void)setupTagDataWithTrack:(id)track
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
	
	/* version strings */
	long version;
	OSErr result;
	result = Gestalt(gestaltQuickTime,&version);
	if (result == noErr)
	{
		added = YES;
		NSString *str = [NSString stringWithFormat:@"X Lossless Decoder %@, QuickTime %d.%d.%d",[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"],(version>>24)&0xF,(version>>20)&0xF,(version>>16)&0xF];
		atomID[0] = 0xa9;
		memcpy(atomID+1,"too",3);
		appendTextTag(tagData, atomID, str);
	}
	
	if(added) {
		int freeSize = 0x800;
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
		file = NULL;
		return NO;
	}
	
	if(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &inputFormat) != noErr) {
		ExtAudioFileDispose(file);
		file = NULL;
		return NO;
	}
	
	if(inputFormat.mSampleRate != outputFormat.mSampleRate) {
		AudioConverterRef converter;
		UInt32 size = sizeof(converter);
		UInt32 quality = kAudioConverterQuality_Max;
		//UInt32 algorithm = 'bats';
		if(ExtAudioFileGetProperty(file, kExtAudioFileProperty_AudioConverter, &size, &converter) != noErr) {
			NSLog(@"ExtAudioFileGetProperty kExtAudioFileProperty_AudioConverter failure");
			ExtAudioFileDispose(file);
			file = NULL;
			return NO;
		}
		
		if(AudioConverterSetProperty(converter, kAudioConverterSampleRateConverterQuality, sizeof(quality), &quality) != noErr) {
			NSLog(@"AudioConverterSetProperty kAudioConverterSampleRateConverterQuality failure");
			ExtAudioFileDispose(file);
			file = NULL;
			return NO;
		}
		/*if(AudioConverterSetProperty(converter, 'srca', sizeof(algorithm), &algorithm) != noErr) {
		 NSLog(@"AudioConverterSetProperty kAudioConverterSampleRateConverterComplexity failure");
		 ExtAudioFileDispose(file);
		 file = NULL;
		 return NO;
		 }*/
		
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
	}
	
	path = [str retain];
	if([configurations objectForKey:@"EmbedChapter"])
		embedChapter = [[configurations objectForKey:@"EmbedChapter"] boolValue];
	
	/* construct tag data */
	if(addTag) {
		[self setupTagDataWithTrack:track];
	}
	/* construct chapter data */
	if(embedChapter && [[track metadata] objectForKey:XLD_METADATA_TRACKLIST] && [[track metadata] objectForKey:XLD_METADATA_TOTALSAMPLES]) {
		NSData *chapterTrack = buildChapterTrack([[[track metadata] objectForKey:XLD_METADATA_TOTALSAMPLES] unsignedIntValue], format.samplerate, [[track metadata] objectForKey:XLD_METADATA_TRACKLIST]);
		chapterMdat = [buildChapterData([[track metadata] objectForKey:XLD_METADATA_TRACKLIST]) retain];
		[tagData replaceBytesInRange:NSMakeRange(0, 0) withBytes:[chapterTrack bytes] length:[chapterTrack length]];
	}
			
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
	fillBufList.mBuffers[0].mDataByteSize = counts*format.bps*format.channels;
	
	if(format.bps != 4 && encodebufSize < fillBufList.mBuffers[0].mDataByteSize) {
		encodebuf = realloc(encodebuf,fillBufList.mBuffers[0].mDataByteSize);
		encodebufSize = fillBufList.mBuffers[0].mDataByteSize;
	}
	
	fillBufList.mBuffers[0].mData = encodebuf;
	
	int i;
	switch(format.bps) {
		case 2:
			for(i=0;i<counts*format.channels;i++) {
				*((short *)encodebuf+i) = *(buffer+i) >> 16;
			}
			break;
		case 3:
#ifdef _BIG_ENDIAN
			for(i=0;i<counts*format.channels;i++) {
				*((char *)encodebuf+i*3) = *((char *)buffer+i*4);
				*((char *)encodebuf+i*3+1) = *((char *)buffer+i*4+1);
				*((char *)encodebuf+i*3+2) = *((char *)buffer+i*4+2);
			}
#else
			for(i=0;i<counts*format.channels;i++) {
				*((char *)encodebuf+i*3) = *((char *)buffer+i*4+1);
				*((char *)encodebuf+i*3+1) = *((char *)buffer+i*4+2);
				*((char *)encodebuf+i*3+2) = *((char *)buffer+i*4+3);
			}
#endif
			break;
		case 4:
			fillBufList.mBuffers[0].mData = buffer;
	}
	
	if(ExtAudioFileWrite(file, counts, &fillBufList) != noErr) {
		return NO;
	}
	
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
	
	updateM4aFileInfo(fp);
	
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
	int i;
	int tmp;
	char atom[4];
	int *stco = NULL;
	struct stat stbuf;
	stat([path UTF8String], &stbuf);
	
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
	if(addTag && [tagData length]) {
		
		int tmp;
		int udtaSize = [tagData length];
		off_t origSize;
		char atom[4];
		struct stat stbuf;
		
		stat([path UTF8String], &stbuf);
		origSize = stbuf.st_size;
		
		FILE *fp = fopen([path UTF8String], "r+b");
		if(!fp) return;
		int bufferSize = 1024*1024;
		char *tmpbuf = (char *)malloc(bufferSize);
		char *tmpbuf2 = (char *)malloc(bufferSize);
		char *read = tmpbuf;
		char *write = tmpbuf2;
		char *swap;
		BOOL moov_after_mdat = NO;
		
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
					int i;
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
		
		if(moov_after_mdat) {
			goto beginWrite;
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
		
		int i;
		for(i=0;i<nElement;i++) {
			stco[2+i] = SWAP32(SWAP32(stco[2+i])+udtaSize);
		}
		if(fseeko(fp,8-tmp,SEEK_CUR) != 0) goto end;
		if(fwrite(stco,1,tmp-8,fp) < tmp-8) goto end;
		
		free(stco);
		
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
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}


@end
