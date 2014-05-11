//
//  XLDDSDDecoder.m
//  XLDDSDDecoder
//
//  Created by tmkk on 14/05/10.
//  Copyright 2014 tmkk. All rights reserved.
//

#import "XLDDSDDecoder.h"
#import "id3lib.h"

#define OUTPUT_HZ 352800

static inline void convertSamples(int *dst, float *src, int numSamples)
{
#if 1
	int i;
	for(i=0;i<numSamples;i++) {
#ifdef __i386__
		float value = src[i] * 8388608;
		int rounded;
		__asm__ (
			"cvtss2si	%1, %0\n\t"
			: "=r"(rounded)
			: "x"(value)
		);
#else
		float fix = src[i] >= 0 ? 0.5 : -0.5;
		int rounded = (int)(src[i] * 8388608 + fix);
#endif
		if(rounded < -8388608) dst[i] = -8388608 << 8;
		else if(rounded > 8388607) dst[i] = 8388607 << 8;
		else dst[i] = rounded << 8;
	}
#else
	static float __attribute__((aligned(16))) scale[4] = {8388608.0f, 8388608.0f, 8388608.0f, 8388608.0f};
	static int __attribute__((aligned(16))) max[4] = {8388607, 8388607, 8388607, 8388607};
	static int __attribute__((aligned(16))) min[4] = {-8388608, -8388608, -8388608, -8388608};
	__asm__ __volatile__(
		"movups		(src), %%xmm0\n\t"
		"movups		16(src), %%xmm1\n\t"
		"mulps		scale, %xmm0\n\t"
		"mulps		scale, %xmm1\n\t"
		"cvtps2dq	%%xmm0, %%xmm0\n\t"
		"cvtps2dq	%%xmm1, %%xmm1\n\t"
		"movdqa		%%xmm0, %%xmm2\n\t"
		"movdqa		%%xmm1, %%xmm3\n\t"
		"movdqa		%%xmm0, %%xmm4\n\t"
		"movdqa		%%xmm1, %%xmm5\n\t"
		"psrld		%%xmm2, %%xmm2\n\t"
		"psrld		%%xmm3, %%xmm3\n\t"
		"pxor		%%xmm2, %%xmm0\n\t"
		"pxor		%%xmm3, %%xmm1\n\t"
		"psubd		%%xmm2, %%xmm0\n\t"
		"psubd		%%xmm3, %%xmm1\n\t"
		);
#endif
}

@implementation XLDDSDDecoder

+ (BOOL)canHandleFile:(char *)path
{
	FILE *fp = fopen(path, "rb");
	if(!fp) return NO;
	
	char buf[4];
	int tmp;
	uint64_t tmp2;
	int ret = fread(buf, 1, 4, fp);
	if(ret < 4) goto fail;
	if(!memcmp(buf, "DSD ", 4)) {
		if(fread(&tmp2, 8, 1, fp) < 1) goto fail;
		tmp2 = OSSwapLittleToHostInt64(tmp2);
		if(fseeko(fp, tmp2-12, SEEK_CUR) != 0) goto fail;
		
		off_t pos = ftello(fp);
		while(1) { //skip until fmt;
			if(fread(buf,1,4,fp) < 4) goto fail;
			if(fread(&tmp2,8,1,fp) < 1) goto fail;
			tmp2 = OSSwapLittleToHostInt64(tmp2);
			if(!memcmp(buf,"fmt ",4)) break;
			if(fseeko(fp,tmp2-12,SEEK_CUR) != 0) goto fail;
		}
		if(fread(&tmp, 4, 1, fp) < 1) goto fail;
		tmp = OSSwapLittleToHostInt32(tmp);
		if(tmp != 1) goto fail;
		if(fread(&tmp, 4, 1, fp) < 1) goto fail;
		tmp = OSSwapLittleToHostInt32(tmp);
		if(tmp != 0) goto fail;
		if(fseeko(fp, 8, SEEK_CUR) != 0) goto fail;
		if(fread(&tmp, 4, 1, fp) < 1) goto fail;
		tmp = OSSwapLittleToHostInt32(tmp);
		if(tmp != 2822400 && tmp != 5644800) goto fail;
		if(fread(&tmp, 4, 1, fp) < 1) goto fail;
		tmp = OSSwapLittleToHostInt32(tmp);
		if(tmp != 1) goto fail;
		if(fseeko(fp, pos, SEEK_SET) != 0) goto fail;
		
		while(1) { //skip until data;
			if(fread(buf,1,4,fp) < 4) goto fail;
			if(fread(&tmp2,8,1,fp) < 1) goto fail;
			tmp2 = OSSwapLittleToHostInt64(tmp2);
			if(!memcmp(buf,"data",4)) break;
			if(fseeko(fp,tmp2-12,SEEK_CUR) != 0) goto fail;
		}
	}
	else if(!memcmp(buf, "FRM8", 4)) {
		if(fseeko(fp, 8, SEEK_CUR) != 0) goto fail;
		ret = fread(buf, 1, 4, fp);
		if(ret < 4) goto fail;
		if(memcmp(buf, "DSD ", 4)) goto fail;
		
		off_t pos = ftello(fp);
		int read;
		int size;
		while(1) { //skip until PROP;
			if(fread(buf,1,4,fp) < 4) goto fail;
			if(fread(&tmp2,8,1,fp) < 1) goto fail;
			tmp2 = OSSwapBigToHostInt64(tmp2);
			if(!memcmp(buf,"PROP",4)) break;
			if(fseeko(fp,tmp2,SEEK_CUR) != 0) goto fail;
		}
		size = tmp2;
		if(fread(buf,1,4,fp) < 4) goto fail;
		if(memcmp(buf, "SND ", 4)) goto fail;
		
		read = 4;
		int fs = 0;
		int dsd = 0;
		while(read < size) {
			if(fread(buf,1,4,fp) < 4) goto fail;
			if(fread(&tmp2,8,1,fp) < 1) goto fail;
			tmp2 = OSSwapBigToHostInt64(tmp2);
			if(!memcmp(buf,"FS  ",4)) {
				if(fread(&tmp,4,1,fp) < 1) goto fail;
				fs = OSSwapBigToHostInt32(tmp);
			}
			else if(!memcmp(buf,"CMPR",4)) {
				if(fread(buf,1,4,fp) < 4) goto fail;
				if(!memcmp(buf,"DSD ",4)) dsd = 1;
				if(fseeko(fp,tmp2-4,SEEK_CUR) != 0) goto fail;
			}
			else if(fseeko(fp,tmp2,SEEK_CUR) != 0) goto fail;
			read += tmp2 + 12;
		}
		if((fs != 2822400 && fs != 5644800) || !dsd) goto fail;
		
		if(fseeko(fp,pos,SEEK_SET) != 0) goto fail;
		while(1) { //skip until DSD;
			if(fread(buf,1,4,fp) < 4) goto fail;
			if(fread(&tmp2,8,1,fp) < 1) goto fail;
			tmp2 = OSSwapBigToHostInt64(tmp2);
			if(!memcmp(buf,"DSD ",4)) break;
			if(fseeko(fp,tmp2,SEEK_CUR) != 0) goto fail;
		}
	}
	else goto fail;
	fclose(fp);
	return YES;
fail:
	fclose(fp);
	return NO;
}

+ (BOOL)canLoadThisBundle
{
	return YES;
}

- (BOOL)openFile:(char *)path
{
	dsd_fp = fopen(path, "rb");
	if(!dsd_fp) return NO;
	
	char buf[4];
	int tmp;
	uint64_t tmp2;
	short tmp3;
	int ret = fread(buf, 1, 4, dsd_fp);
	if(ret < 4) goto fail;
	if(!memcmp(buf, "DSD ", 4)) {
		off_t pos_tag = 0;
		if(fread(&tmp2, 8, 1, dsd_fp) < 1) goto fail;
		tmp2 = OSSwapLittleToHostInt64(tmp2);
		if(tmp2 < 28) return NO;
		if(fseeko(dsd_fp, 8, SEEK_CUR) != 0) goto fail;
		if(fread(&pos_tag, 8, 1, dsd_fp) < 1) goto fail;
		pos_tag = OSSwapLittleToHostInt64(pos_tag);
		if(fseeko(dsd_fp, tmp2-28, SEEK_CUR) != 0) goto fail;
		
		off_t pos = ftello(dsd_fp);
		while(1) { //skip until fmt;
			if(fread(buf,1,4,dsd_fp) < 4) goto fail;
			if(fread(&tmp2,8,1,dsd_fp) < 1) goto fail;
			tmp2 = OSSwapLittleToHostInt64(tmp2);
			if(!memcmp(buf,"fmt ",4)) break;
			if(fseeko(dsd_fp,tmp2-12,SEEK_CUR) != 0) goto fail;
		}
		
		if(fread(&tmp, 4, 1, dsd_fp) < 1) goto fail;
		tmp = OSSwapLittleToHostInt32(tmp);
		if(tmp != 1) goto fail;
		if(fread(&tmp, 4, 1, dsd_fp) < 1) goto fail;
		tmp = OSSwapLittleToHostInt32(tmp);
		if(tmp != 0) goto fail;
		if(fseeko(dsd_fp, 4, SEEK_CUR) != 0) goto fail;
		if(fread(&tmp, 4, 1, dsd_fp) < 1) goto fail;
		channels = OSSwapLittleToHostInt32(tmp);
		if(fread(&tmp, 4, 1, dsd_fp) < 1) goto fail;
		samplerate = OSSwapLittleToHostInt32(tmp);
		if(samplerate != 2822400 && samplerate != 5644800) goto fail;
		if(fread(&tmp, 4, 1, dsd_fp) < 1) goto fail;
		tmp = OSSwapLittleToHostInt32(tmp);
		if(tmp != 1) goto fail;
		if(fread(&tmp2, 8, 1, dsd_fp) < 1) goto fail;
		totalDSDSamples = OSSwapLittleToHostInt64(tmp2);
		totalPCMSamples = totalDSDSamples / 8;
		if(fread(&tmp, 4, 1, dsd_fp) < 1) goto fail;
		blockSize = OSSwapLittleToHostInt32(tmp) * channels;
		if(fseeko(dsd_fp, pos, SEEK_SET) != 0) goto fail;
		
		while(1) { //skip until data;
			if(fread(buf,1,4,dsd_fp) < 4) goto fail;
			if(fread(&tmp2,8,1,dsd_fp) < 1) goto fail;
			tmp2 = OSSwapLittleToHostInt64(tmp2);
			if(!memcmp(buf,"data",4)) break;
			if(fseeko(dsd_fp,tmp2-12,SEEK_CUR) != 0) goto fail;
		}
		dataStart = ftello(dsd_fp);
		
		if(fseeko(dsd_fp, pos_tag, SEEK_SET) != 0) goto fail;
		if(fread(buf, 1, 3, dsd_fp) < 3) goto fail;
		if(!memcmp(buf, "ID3", 3)) {
			int tagSize = 10;
			unsigned char tmp4;
			if(fseeko(dsd_fp, 3, SEEK_CUR) != 0) goto fail;
			if(fread(&tmp4, 1, 1, dsd_fp) < 1) goto fail;
			tagSize += (tmp4 & 0x7f) << 21;
			if(fread(&tmp4, 1, 1, dsd_fp) < 1) goto fail;
			tagSize += (tmp4 & 0x7f) << 14;
			if(fread(&tmp4, 1, 1, dsd_fp) < 1) goto fail;
			tagSize += (tmp4 & 0x7f) << 7;
			if(fread(&tmp4, 1, 1, dsd_fp) < 1) goto fail;
			tagSize += tmp4 & 0x7f;
			char *tagBuf = malloc(tagSize);
			if(fseeko(dsd_fp, pos_tag, SEEK_SET) != 0) goto fail;
			if(fread(tagBuf, 1, tagSize, dsd_fp) < tagSize) goto fail;
			NSData *dat = [NSData dataWithBytesNoCopy:tagBuf length:tagSize];
			metadataDic = [[NSMutableDictionary alloc] init];
			parseID3(dat,metadataDic);
		}
		if(fseeko(dsd_fp, dataStart, SEEK_SET) != 0) goto fail;
		
		DSDSamplesPerBlock = blockSize * 8 / channels;
		PCMSamplesPerBlock = blockSize / channels;
		totalBlocks = totalDSDSamples / DSDSamplesPerBlock;
		lastBlockDSDSampleCount = totalDSDSamples - totalBlocks * DSDSamplesPerBlock;
		//NSLog(@"%d,%d,%lld,%lld,%d,%d,%lld,%d",blockSize,channels,totalDSDSamples,totalPCMSamples,DSDSamplesPerBlock,PCMSamplesPerBlock,totalBlocks,lastBlockDSDSampleCount);
		
		dsdFormat = XLDDSDFormatDSF;
	}
	else if(!memcmp(buf, "FRM8", 4)) {
		if(fseeko(dsd_fp, 8, SEEK_CUR) != 0) goto fail;
		ret = fread(buf, 1, 4, dsd_fp);
		if(ret < 4) goto fail;
		if(memcmp(buf, "DSD ", 4)) goto fail;
		
		off_t pos = ftello(dsd_fp);
		int read;
		int size;
		while(1) { //skip until PROP;
			if(fread(buf,1,4,dsd_fp) < 4) goto fail;
			if(fread(&tmp2,8,1,dsd_fp) < 1) goto fail;
			tmp2 = OSSwapBigToHostInt64(tmp2);
			if(!memcmp(buf,"PROP",4)) break;
			if(fseeko(dsd_fp,tmp2,SEEK_CUR) != 0) goto fail;
		}
		size = tmp2;
		if(fread(buf,1,4,dsd_fp) < 4) goto fail;
		if(memcmp(buf, "SND ", 4)) goto fail;
		
		read = 4;
		int fs = 0;
		int dsd = 0;
		while(read < size) {
			if(fread(buf,1,4,dsd_fp) < 4) goto fail;
			if(fread(&tmp2,8,1,dsd_fp) < 1) goto fail;
			tmp2 = OSSwapBigToHostInt64(tmp2);
			if(!memcmp(buf,"FS  ",4)) {
				if(fread(&tmp,4,1,dsd_fp) < 1) goto fail;
				fs = OSSwapBigToHostInt32(tmp);
			}
			else if(!memcmp(buf,"CMPR",4)) {
				if(fread(buf,1,4,dsd_fp) < 4) goto fail;
				if(!memcmp(buf,"DSD ",4)) dsd = 1;
				if(fseeko(dsd_fp,tmp2-4,SEEK_CUR) != 0) goto fail;
			}
			else if(!memcmp(buf,"CHNL",4)) {
				if(fread(&tmp3,2,1,dsd_fp) < 1) goto fail;
				channels = OSSwapBigToHostInt16(tmp3);
				if(fseeko(dsd_fp,tmp2-2,SEEK_CUR) != 0) goto fail;
			}
			else if(fseeko(dsd_fp,tmp2,SEEK_CUR) != 0) goto fail;
			read += tmp2 + 12;
		}
		if((fs != 2822400 && fs != 5644800) || !dsd) goto fail;
		samplerate = fs;
		
		if(fseeko(dsd_fp,pos,SEEK_SET) != 0) goto fail;
		while(1) { //skip until DSD;
			if(fread(buf,1,4,dsd_fp) < 4) goto fail;
			if(fread(&tmp2,8,1,dsd_fp) < 1) goto fail;
			tmp2 = OSSwapBigToHostInt64(tmp2);
			if(!memcmp(buf,"DSD ",4)) break;
			if(fseeko(dsd_fp,tmp2,SEEK_CUR) != 0) goto fail;
		}
		dataStart = ftello(dsd_fp);
		
		blockSize = 16384 * channels;
		totalDSDSamples = tmp2 * 8 / channels;
		totalPCMSamples = tmp2 / channels;
		DSDSamplesPerBlock = blockSize * 8 / channels;
		PCMSamplesPerBlock = blockSize / channels;
		totalBlocks = totalDSDSamples / DSDSamplesPerBlock;
		lastBlockDSDSampleCount = totalDSDSamples - totalBlocks * DSDSamplesPerBlock;
		//NSLog(@"%d,%d,%lld,%lld,%d,%d,%lld,%d",blockSize,channels,totalDSDSamples,totalPCMSamples,DSDSamplesPerBlock,PCMSamplesPerBlock,totalBlocks,lastBlockDSDSampleCount);
		
		dsdFormat = XLDDSDFormatDFF;
	}
	else goto fail;
	
	dsdBuffer = malloc(blockSize);
	pcmBuffer = malloc(blockSize*sizeof(float));
	residueBuffer = malloc(blockSize*sizeof(float));
	dsdProc = malloc(sizeof(dsd2pcm_ctx*) * channels);
	int i;
	for(i=0;i<channels;i++) {
		dsdProc[i] = dsd2pcm_init();
	}
	
	outSamplerate = [[[NSBundle bundleWithIdentifier:@"jp.tmkk.XLDDSDDecoder"] objectForInfoDictionaryKey: @"XLDDSDDecoderOutputSamplerate"] intValue];
	if(outSamplerate >= samplerate / 8 || outSamplerate < 0) outSamplerate = 0;
	if(outSamplerate) {
		soxr_error_t err;
		soxr_io_spec_t spec = soxr_io_spec(SOXR_FLOAT32_I, SOXR_FLOAT32_I);
		soxr_quality_spec_t qspec = soxr_quality_spec(SOXR_VHQ, 0);
		soxr = soxr_create(samplerate/8,outSamplerate,channels,&err,&spec,&qspec,NULL);
		if(err) {
			fprintf(stderr,"sox resampler initialization error\n");
			return NO;
		}
		resampleBuffer = malloc(blockSize*sizeof(float)*8);
	}
	else outSamplerate = samplerate / 8;
	
	residueSampleCount = 0;
	currentBlock = 0;
	srcPath = [[NSString stringWithUTF8String:path] retain];
	return YES;
fail:
	fclose(dsd_fp);
	return NO;
}

- (int)samplerate
{
	return outSamplerate;
}

- (int)bytesPerSample
{
	return 3;
}

- (int)channels
{
	return channels;
}

- (int)decodeToBuffer:(int *)buffer frames:(int)count
{
	int i;
	if(currentBlock == totalBlocks) {
		if(!residueSampleCount) return 0;
		if(count >= residueSampleCount) {
			convertSamples(buffer,residueBuffer,residueSampleCount*channels);
			int tmp = residueSampleCount;
			residueSampleCount = 0;
			return tmp;
		}
		else {
			convertSamples(buffer,residueBuffer,count*channels);
			memmove(residueBuffer, residueBuffer+count*channels, sizeof(float)*(residueSampleCount - count)*channels);
			residueSampleCount -= count;
			return count;
		}
	}
	else {
		int rest = count;
		int offset = 0;
		if(residueSampleCount) {
			if(rest >= residueSampleCount) {
				convertSamples(buffer,residueBuffer,residueSampleCount*channels);
				rest -= residueSampleCount;
				offset = residueSampleCount * channels;
				residueSampleCount = 0;
			}
			else {
				convertSamples(buffer,residueBuffer,count*channels);
				memmove(residueBuffer, residueBuffer+count*channels, sizeof(float)*(residueSampleCount - count)*channels);
				residueSampleCount -= count;
				return count;
			}
		}
		while(rest && currentBlock < totalBlocks) {
			fread(dsdBuffer,1,blockSize,dsd_fp);
			currentBlock++;
			int currentPCMSamplesPerBlock = PCMSamplesPerBlock;
			if(currentBlock == totalBlocks) currentPCMSamplesPerBlock = lastBlockDSDSampleCount / 8;
			if(dsdFormat == XLDDSDFormatDSF) {
				for(i=0;i<channels;i++) {
					dsd2pcm_translate(dsdProc[i],PCMSamplesPerBlock,dsdBuffer+i*PCMSamplesPerBlock,1,1,pcmBuffer+i,channels);
				}
			}
			else if(dsdFormat == XLDDSDFormatDFF) {
				for(i=0;i<channels;i++) {
					dsd2pcm_translate(dsdProc[i],PCMSamplesPerBlock,dsdBuffer+i,channels,0,pcmBuffer+i,channels);
				}
			}
			if(soxr) {
				size_t done = 0;
				//NSLog(@"%d,%d\n",currentPCMSamplesPerBlock,blockSize/channels);
				soxr_process(soxr,pcmBuffer,currentPCMSamplesPerBlock,NULL,resampleBuffer,blockSize/channels,&done);
				if(currentBlock == totalBlocks) {
					size_t done2 = 0;
					soxr_process(soxr,NULL,0,NULL,resampleBuffer+done*channels,blockSize/channels,&done2);
					done += done2;
				}
				if(rest >= done) {
					convertSamples(buffer+offset,resampleBuffer,done*channels);
					rest -= done;
					offset += done * channels;
				}
				else {
					convertSamples(buffer+offset,resampleBuffer,rest*channels);
					memcpy(residueBuffer, resampleBuffer+rest*channels, sizeof(float)*(done - rest)*channels);
					residueSampleCount = done - rest;
					rest = 0;
				}
			}
			else {
				if(rest >= currentPCMSamplesPerBlock) {
					convertSamples(buffer+offset,pcmBuffer,currentPCMSamplesPerBlock*channels);
					rest -= currentPCMSamplesPerBlock;
					offset += currentPCMSamplesPerBlock * channels;
				}
				else {
					convertSamples(buffer+offset,pcmBuffer,rest*channels);
					memcpy(residueBuffer, pcmBuffer+rest*channels, sizeof(float)*(currentPCMSamplesPerBlock - rest)*channels);
					residueSampleCount = currentPCMSamplesPerBlock - rest;
					rest = 0;
				}
			}
		}
		return count - rest;
	}
	return 0;
}

- (void)closeFile
{
	if(dsd_fp) fclose(dsd_fp);
	dsd_fp = NULL;
	if(pcmBuffer) free(pcmBuffer);
	pcmBuffer = NULL;
	if(dsdBuffer) free(dsdBuffer);
	dsdBuffer = NULL;
	if(residueBuffer) free(residueBuffer);
	residueBuffer = NULL;
	if(resampleBuffer) free(resampleBuffer);
	resampleBuffer = NULL;
	if(dsdProc) {
		int i;
		for(i<0;i<channels;i++) {
			dsd2pcm_destroy(dsdProc[i]);
		}
		free(dsdProc);
		dsdProc = NULL;
	}
	if(srcPath) [srcPath release];
	srcPath = nil;
	if(metadataDic) [metadataDic release];
	metadataDic = nil;
	if(soxr) soxr_delete(soxr);
	soxr = NULL;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	int i;
	for(i=0;i<channels;i++) {
		dsd2pcm_reset(dsdProc[i]);
	}
	if(soxr) {
		double scale = (double)samplerate / outSamplerate / 8.0;
		scale = scale * count + 0.5;
		count = (xldoffset_t)scale;
		soxr_delete(soxr);
		soxr_error_t err;
		soxr_io_spec_t spec = soxr_io_spec(SOXR_FLOAT32_I, SOXR_FLOAT32_I);;
		soxr_quality_spec_t qspec = soxr_quality_spec(SOXR_VHQ, 0);
		soxr = soxr_create(samplerate/8,outSamplerate,channels,&err,&spec,&qspec,NULL);
	}
	if(count > totalPCMSamples) count = totalPCMSamples;
	currentBlock = count / PCMSamplesPerBlock;
	fseeko(dsd_fp, dataStart+blockSize*currentBlock, SEEK_SET);
	residueSampleCount = 0;
	if(count == 0) return count;
	int start = count - currentBlock * PCMSamplesPerBlock;
	fread(dsdBuffer,1,blockSize,dsd_fp);
	currentBlock++;
	if(dsdFormat == XLDDSDFormatDSF) {
		for(i=0;i<channels;i++) {
			dsd2pcm_translate(dsdProc[i],PCMSamplesPerBlock,dsdBuffer+i*PCMSamplesPerBlock,1,1,pcmBuffer+i,channels);
		}
	}
	else if(dsdFormat == XLDDSDFormatDFF) {
		for(i=0;i<channels;i++) {
			dsd2pcm_translate(dsdProc[i],PCMSamplesPerBlock,dsdBuffer+i,channels,0,pcmBuffer+i,channels);
		}
	}
	if(soxr) {
		size_t done = 0;
		soxr_process(soxr,pcmBuffer+start*channels,PCMSamplesPerBlock - start,NULL,resampleBuffer,blockSize/channels,&done);
		memcpy(residueBuffer,resampleBuffer,sizeof(float)*channels*done);
		residueSampleCount = done;
	}
	else {
		memcpy(residueBuffer,pcmBuffer+start*channels,sizeof(float)*channels*(PCMSamplesPerBlock - start));
		residueSampleCount = PCMSamplesPerBlock - start;
	}
	
	return count;
}

- (xldoffset_t)totalFrames
{
	if(soxr) {
		double scale = outSamplerate * 8.0 / samplerate;
		scale = scale * totalPCMSamples + 0.5;
		return (xldoffset_t)scale;
	}
	return totalPCMSamples;
}

- (int)isFloat
{
	return 0;
}

- (BOOL)error
{
	return NO;
}

- (XLDEmbeddedCueSheetType)hasCueSheet
{
	return XLDNoCueSheet;
}

- (id)cueSheet
{
	return nil;
}

- (id)metadata
{
	return metadataDic;
}

- (NSString *)srcPath
{
	return srcPath;
}

@end
