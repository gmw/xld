//
//  XLDSACDISOReader.m
//  XLDDSDDecoder
//
//  Created by tmkk on 14/11/16.
//  Copyright 2014 tmkk. All rights reserved.
//

typedef int64_t xldoffset_t;
#import "XLDSACDISOReader.h"
#import "XLDTrack.h"
#import "DST/dst_decoder.h"

#define XLD_METADATA_TITLE		@"Title"
#define XLD_METADATA_ARTIST		@"Artist"
#define XLD_METADATA_ALBUM		@"Album"
#define XLD_METADATA_GENRE		@"Genre"
#define XLD_METADATA_TRACK		@"Track"
#define XLD_METADATA_DISC		@"Disc"
#define XLD_METADATA_YEAR		@"Year"
#define XLD_METADATA_DATE		@"Date"
#define XLD_METADATA_COMPOSER	@"Composer"
#define XLD_METADATA_CUESHEET	@"Cuesheet"
#define XLD_METADATA_COMMENT	@"Comment"
#define XLD_METADATA_TOTALTRACKS	@"Totaltracks"
#define XLD_METADATA_TOTALDISCS	@"Totaldiscs"
#define XLD_METADATA_LYRICS		@"Lyrics"
#define XLD_METADATA_ISRC		@"ISRC"
#define XLD_METADATA_COVER		@"Cover"
#define XLD_METADATA_ALBUMARTIST	@"AlbumArtist"
#define XLD_METADATA_REPLAYGAIN_TRACK_GAIN	@"RGTrackGain"
#define XLD_METADATA_REPLAYGAIN_ALBUM_GAIN	@"RGAlbumGain"
#define XLD_METADATA_REPLAYGAIN_TRACK_PEAK	@"RGTrackPeak"
#define XLD_METADATA_REPLAYGAIN_ALBUM_PEAK	@"RGAlbumPeak"
#define XLD_METADATA_COMPILATION	@"Compilation"
#define XLD_METADATA_GROUP		@"Group"
#define XLD_METADATA_GRACENOTE		@"Gracenote"
#define XLD_METADATA_CATALOG		@"Catalog"
#define XLD_METADATA_PREEMPHASIS	@"Emphasis"
#define XLD_METADATA_DCP		@"DCP"
#define XLD_METADATA_FREEDBDISCID	@"DISCID"
#define XLD_METADATA_BPM		@"BPM"
#define XLD_METADATA_COPYRIGHT	@"Copyright"
#define XLD_METADATA_GAPLESSALBUM	@"GaplessAlbum"
#define XLD_METADATA_CREATIONDATE	@"CreationDate"
#define XLD_METADATA_MODIFICATIONDATE	@"ModificationDate"
#define XLD_METADATA_ORIGINALFILENAME	@"OriginalFilename"
#define XLD_METADATA_ORIGINALFILEPATH	@"OriginalFilepath"
#define XLD_METADATA_DATATRACK @"DataTrack"
#define XLD_METADATA_TITLESORT	@"TitleSort"
#define XLD_METADATA_ARTISTSORT	@"ArtistSort"
#define XLD_METADATA_ALBUMSORT	@"AlbumSort"
#define XLD_METADATA_ALBUMARTISTSORT	@"AlbumArtistSort"
#define XLD_METADATA_COMPOSERSORT	@"ComposerSort"
#define XLD_METADATA_GRACENOTE2		@"Gracenote2"
#define XLD_METADATA_MB_TRACKID		@"MusicBrainz_TrackID"
#define XLD_METADATA_MB_ALBUMID	@"MusicBrainz_AlbumID"
#define XLD_METADATA_MB_ARTISTID	@"MusicBrainz_ArtistID"
#define XLD_METADATA_MB_ALBUMARTISTID	@"MusicBrainz_AlbumArtistID"
#define XLD_METADATA_MB_DISCID	@"MusicBrainz_DiscID"
#define XLD_METADATA_PUID		@"MusicIP_PUID"
#define XLD_METADATA_MB_ALBUMSTATUS	@"MusicBrainz_AlbumStatus"
#define XLD_METADATA_MB_ALBUMTYPE	@"MusicBrainz_AlbumType"
#define XLD_METADATA_MB_RELEASECOUNTRY	@"MusicBrainz_ReleaseCountry"
#define XLD_METADATA_MB_RELEASEGROUPID	@"MusicBrainz_ReleaseGroupID"
#define XLD_METADATA_MB_WORKID	@"MusicBrainz_WorkID"
#define XLD_METADATA_TOTALSAMPLES	@"TotalSamples"
#define XLD_METADATA_TRACKLIST	@"XLDTrackList"
#define XLD_METADATA_SMPTE_TIMECODE_START	@"SMTPE Timecode Start"
#define XLD_METADATA_SMPTE_TIMECODE_DURATION	@"SMTPE Timecode Duration"
#define XLD_METADATA_MEDIA_FPS	@"Media FPS"
#define XLD_METADATA_FINDERLABEL @"Finder Label"

@implementation XLDSACDISOReader

- (id)init
{
	self = [super init];
	if(!self) return nil;
	
	trackList = [[NSMutableArray alloc] init];
	buffer = malloc(588*2*8*8);
	dstBuffer = malloc(2048*6);
	dstDecoder = calloc(1,sizeof(ebunch));
	DSTDecoderInit(dstDecoder,2,64);
	return self;
}

- (void)dealloc
{
	[trackList release];
	free(buffer);
	free(dstBuffer);
	DSTDecoderClose(dstDecoder);
	free(dstDecoder);
	[self closeFile];
	[super dealloc];
}

- (BOOL)openFile:(NSString *)path
{
	fp = fopen([path UTF8String], "rb");
	if(!fp) return NO;
	
	if(fseeko(fp,2048*510,SEEK_SET)) goto fail;
	char header[8];
	if(fread(header,1,8,fp) != 8) goto fail;
	if(memcmp(header,"SACDMTOC",8)) goto fail;
	
	uint8_t tmp8;
	uint16_t tmp16;
	uint32_t tmp32;
	off_t areaTocOffset1;
	off_t areaTocOffset2;
	
	if(fread(&tmp16,2,1,fp) != 1) goto fail;
	//if(OSSwapBigToHostInt16(tmp16) != 0x114) goto fail;
	if(fseeko(fp,54,SEEK_CUR)) goto fail;
	if(fread(&tmp32,4,1,fp) != 1) goto fail;
	areaTocOffset1 = (off_t)OSSwapBigToHostInt32(tmp32) * 2048;
	if(fread(&tmp32,4,1,fp) != 1) goto fail;
	areaTocOffset2 = (off_t)OSSwapBigToHostInt32(tmp32) * 2048;
	
	if(!areaTocOffset1 && !areaTocOffset2) goto fail;
	
	unsigned int flagTRL = 0;
	if(areaTocOffset1) {
		int nSectors;
		if(fseeko(fp,areaTocOffset1,SEEK_SET)) goto fail;
		if(fread(header,1,8,fp) != 8) goto fail;
		if(memcmp(header,"TWOCHTOC",8)) goto fail;
		if(fseeko(fp,2,SEEK_CUR)) goto fail;
		if(fread(&tmp16,2,1,fp) != 1) goto fail;
		nSectors = OSSwapBigToHostInt16(tmp16) - 1;
		if(fseeko(fp,52,SEEK_CUR)) goto fail;
		if(fread(&tmp8,1,1,fp) != 1) goto fail;
		totalSamples =  (xldoffset_t)tmp8 * 75 * 60;
		if(fread(&tmp8,1,1,fp) != 1) goto fail;
		totalSamples +=  (xldoffset_t)tmp8 * 75;
		if(fread(&tmp8,1,1,fp) != 1) goto fail;
		totalSamples +=  (xldoffset_t)tmp8;
		totalSamples -= 150; /* 2 seconds offset */
		totalSamples = totalSamples * 37632;
		if(fseeko(fp,2,SEEK_CUR)) goto fail;
		if(fread(&tmp8,1,1,fp) != 1) goto fail;
		numTracks = tmp8;
		
		if(numTracks <= 0) goto fail;
		if(fseeko(fp,1978,SEEK_CUR)) goto fail;
		
		while(nSectors > 0) {
			if(fread(header,1,8,fp) != 8) goto fail;
			if(!memcmp(header,"SACDTTxt",8)) {
				if(fseeko(fp,2040,SEEK_CUR)) goto fail;
				nSectors--;
			}
			else if(!memcmp(header,"SACD_IGL",8)) {
				if(fseeko(fp,4088,SEEK_CUR)) goto fail;
				nSectors -= 2;
			}
			else if(!memcmp(header,"SACD_ACC",8)) {
				if(fseeko(fp,2048*32-8,SEEK_CUR)) goto fail;
				nSectors -= 32;
			}
			else if(!memcmp(header,"SACDTRL1",8)) {
				int i;
				off_t start = ftello(fp);
				for(i=0;i<numTracks;i++) {
					if(fread(&tmp32,4,1,fp) != 1) goto fail;
					trackLSN[i] = OSSwapBigToHostInt32(tmp32);
				}
				if(fseeko(fp,4*254,SEEK_CUR)) goto fail;
				if(fread(&tmp32,4,1,fp) != 1) goto fail;
				trackLSN[numTracks] = trackLSN[numTracks-1] + OSSwapBigToHostInt32(tmp32);
				if(fseeko(fp,start+2040,SEEK_SET)) goto fail;
				nSectors--;
				flagTRL |= 1;
			}
			else if(!memcmp(header,"SACDTRL2",8)) {
				int i;
				off_t start = ftello(fp);
				for(i=0;i<numTracks;i++) {
					if(fread(&tmp32,4,1,fp) != 1) goto fail;
					tmp32 = OSSwapBigToHostInt32(tmp32);
					int MM = tmp32 >> 24;
					int SS = (tmp32 >> 16) & 0xff;
					int FF = (tmp32 >> 8) & 0xff;
					xldoffset_t idx = (xldoffset_t)MM * 60 * 75;
					idx += (xldoffset_t)SS * 75;
					idx += FF;
					idx -= 150; /* 2 seconds offset */
					XLDTrack *track = [[objc_getClass("XLDTrack") alloc] init];
					[[track metadata] setObject:[NSNumber numberWithInt:i+1] forKey:XLD_METADATA_TRACK];
					[[track metadata] setObject:[NSNumber numberWithInt:numTracks] forKey:XLD_METADATA_TOTALTRACKS];
					[track setIndex:idx];
					if(fseeko(fp,4*254,SEEK_CUR)) goto fail;
					if(fread(&tmp32,4,1,fp) != 1) goto fail;
					tmp32 = OSSwapBigToHostInt32(tmp32);
					MM = tmp32 >> 24;
					SS = (tmp32 >> 16) & 0xff;
					FF = (tmp32 >> 8) & 0xff;
					xldoffset_t duration = (xldoffset_t)MM * 60 * 75;
					duration += (xldoffset_t)SS * 75;
					duration += FF;
					[track setFrames:duration];
					if(i > 0) {
						XLDTrack *previous = [trackList objectAtIndex:i-1];
						xldoffset_t gap = [track index] - ([previous index] + [previous frames]);
						[track setGap:gap];
					}
					else if(idx != 0) {
						[track setGap:idx];
					}
					[trackList addObject:track];
					[track release];
					if(fseeko(fp,-4*255,SEEK_CUR)) goto fail;
					flagTRL |= 2;
				}
				if(fseeko(fp,start+2040,SEEK_SET)) goto fail;
				nSectors--;
			}
			else {
				if(fseeko(fp,2040,SEEK_CUR)) goto fail;
				nSectors--;
			}
		}
	}
	
	if(flagTRL != 3) goto fail;
	
	currentLSN = trackLSN[0];
	off_t offset = (off_t)currentLSN * 2048;
	if(fseeko(fp,offset,SEEK_SET)) goto fail;
	/*if(fread(&tmp8,1,1,fp) != 1) goto fail;
	if(tmp8 & 1) goto fail; // doesn't support DST encoded track!
	if(fseeko(fp,-1,SEEK_CUR)) goto fail;*/
	
	[self seekTo:0];
	return YES;
	
fail:
	fclose(fp);
	fp = NULL;
	return NO;
}

- (int)readBytes:(unsigned char*)buf size:(int)size
{
	unsigned char tmp8;
	unsigned short tmp16;
	int read = 0;
	
	if(bytesInBuffer) {
		if(bytesInBuffer <= size) {
			memcpy(buf,buffer,bytesInBuffer);
			size -= bytesInBuffer;
			read = bytesInBuffer;
			bytesInBuffer = 0;
		}
		else {
			memcpy(buf,buffer,size);
			bytesInBuffer -= size;
			memmove(buffer,buffer+size,bytesInBuffer);
			read = size;
			size = 0;
		}
	}
	
	while(size && currentLSN < trackLSN[numTracks]) {
		int nPacketInfo;
		int nFrameInfo;
		int dstEncoded;
		int frameStart[7];
		int packetType[7];
		int packetLength[7];
		off_t sectorBegin = ftello(fp);
		
		int ret = fread(&tmp8,1,1,fp);
		if(ret < 1) break;
		nPacketInfo = tmp8 >> 5;
		nFrameInfo = (tmp8 >> 2) & 0x07;
		dstEncoded = tmp8 & 1;
		int i;
		for(i=0;i<nPacketInfo;i++) {
			ret = fread(&tmp16,2,1,fp);
			if(ret < 1) break;
			tmp16 = OSSwapBigToHostInt16(tmp16);
			frameStart[i] = tmp16 >> 15;
			packetType[i] = (tmp16 >> 11) & 0x7;
			packetLength[i] = tmp16 & 0x7ff;
		}
		for(i=0;i<nFrameInfo;i++) {
			if(dstEncoded) fseeko(fp,4,SEEK_CUR);
			else fseeko(fp,3,SEEK_CUR);
		}
		for(i=0;i<nPacketInfo;i++) {
			if(packetType[i] == 2) {
				if(!dstEncoded) {
					if(packetLength[i] <= size) {
						ret = fread(buf+read,1,packetLength[i],fp);
						size -= ret;
						read += ret;
						if(ret < packetLength[i]) break;
					}
					else {
						if(size) {
							ret = fread(buf+read,1,size,fp);
							size -= ret;
							read += ret;
							if(size != 0) break;
						}
						else ret = 0;
						ret = fread(buffer+bytesInBuffer,1,packetLength[i]-ret,fp);
						bytesInBuffer += ret;
					}
				}
				else {
					if(frameStart[i] && bytesInDSTBuffer) {
						ret = DSTDecoderDecode(dstDecoder, dstBuffer, buffer+bytesInBuffer, 0, &bytesInDSTBuffer);
						bytesInBuffer += 588*2*8;
						bytesInDSTBuffer = 0;
						if(bytesInBuffer <= size) {
							memcpy(buf+read,buffer,bytesInBuffer);
							size -= bytesInBuffer;
							read += bytesInBuffer;
							bytesInBuffer = 0;
						}
						else {
							memcpy(buf+read,buffer,size);
							bytesInBuffer -= size;
							memmove(buffer,buffer+size,bytesInBuffer);
							read += size;
							size = 0;
						}
					}
					ret = fread(dstBuffer+bytesInDSTBuffer,1,packetLength[i],fp);
					bytesInDSTBuffer += ret;
				}
			}
			else fseeko(fp,packetLength[i],SEEK_CUR);
		}
		fseeko(fp, sectorBegin+2048, SEEK_SET);
		currentLSN++;
	}
	return read;
}

- (BOOL)seekTo:(off_t)pos
{
	int i;
	for(i=1;i<numTracks;i++) {
		XLDTrack *track = [trackList objectAtIndex:i];
		if([track index]*588*8*2 > pos) break;
	}
	double posInTrack = pos - [(XLDTrack *)[trackList objectAtIndex:i-1] index]*588*8*2;
	double trackLength;
	if(i==numTracks) trackLength = [(XLDTrack *)[trackList objectAtIndex:i-1] frames]*588*8*2;
	else trackLength = ([(XLDTrack *)[trackList objectAtIndex:i] index] - [(XLDTrack *)[trackList objectAtIndex:i-1] index])*588*8*2;
	double relativePos = posInTrack / trackLength;
	currentLSN = trackLSN[i-1] + (int)(relativePos * (trackLSN[i] - trackLSN[i-1]));
	if(currentLSN >= trackLSN[0]+5) currentLSN -= 5;
	
	off_t estimatedPos = (off_t)currentLSN * 2048;
	if(fseeko(fp,estimatedPos,SEEK_SET)) return NO;
	
	bytesInBuffer = 0;
	bytesInDSTBuffer = 0;
	
	unsigned char tmp8;
	unsigned short tmp16;
	unsigned int tmp32;
	off_t diff = 0;
	BOOL mustRead = NO;
	
	while(!mustRead) {
		int nPacketInfo;
		int nFrameInfo;
		int dstEncoded;
		int packetType[7];
		int packetLength[7];
		int frameStart[7];
		int seekpointFrameindex = 0;
		int frameIndex = 0;
		BOOL seekpointFound = NO;
		off_t lastDiff;
		//fprintf(stderr, "current sector:%d\n",currentLSN);
		off_t sectorBegin = ftello(fp);
		int ret = fread(&tmp8,1,1,fp);
		if(ret < 1) break;
		nPacketInfo = tmp8 >> 5;
		nFrameInfo = (tmp8 >> 2) & 0x07;
		dstEncoded = tmp8 & 1;
		for(i=0;i<nPacketInfo;i++) {
			ret = fread(&tmp16,2,1,fp);
			if(ret < 1) break;
			tmp16 = OSSwapBigToHostInt16(tmp16);
			frameStart[i] = tmp16 >> 15;
			packetType[i] = (tmp16 >> 11) & 0x7;
			packetLength[i] = tmp16 & 0x7ff;
		}
		for(i=0;i<nFrameInfo;i++) {
			ret = fread(&tmp32,4,1,fp);
			if(ret < 1) break;
			tmp32 = OSSwapBigToHostInt32(tmp32);
			int minutes = tmp32 >> 24;
			int seconds = (tmp32 >> 16) & 0xff;
			int frames = (tmp32 >> 8) & 0xff;
			off_t offsetInBytes = (off_t)minutes * 75 * 60;
			offsetInBytes += (off_t)seconds * 75;
			offsetInBytes += frames;
			offsetInBytes -= 150;
			offsetInBytes *= 588 * 8 * 2;
			lastDiff = pos - offsetInBytes;
			//fprintf(stdout,"Found frame %02d:%02d:%02d\n",minutes,seconds,frames);
			//fprintf(stdout,"byte offset: %lld, difference: %lld\n",offsetInBytes,lastDiff);
			if(lastDiff >= 0 && lastDiff < 588 * 8 * 2) {
				seekpointFound = YES;
				seekpointFrameindex = i;
				diff = lastDiff;
			}
			if(!dstEncoded) fseeko(fp,-1,SEEK_CUR);
		}
		if(!seekpointFound) {
			if(lastDiff >= 588 * 8 * 2) {
				currentLSN++;
				fseeko(fp, sectorBegin+2048, SEEK_SET);
				goto end;
			}
			else if(lastDiff < 0) {
				currentLSN -= 5;
				fseeko(fp, sectorBegin-10240, SEEK_SET);
				goto end;
			}
		}
		for(i=0;i<nPacketInfo;i++) {
			if(packetType[i] == 2) {
				if(frameStart[i]) {
					if(seekpointFrameindex == frameIndex++) mustRead = YES;
				}
				if(mustRead) {
					if(!dstEncoded) {
						if(packetLength[i] <= diff) {
							fseeko(fp,packetLength[i],SEEK_CUR);
							diff -= packetLength[i];
						}
						else {
							if(diff) fseeko(fp,diff,SEEK_CUR);
							ret = fread(buffer+bytesInBuffer,1,packetLength[i]-diff,fp);
							bytesInBuffer += ret;
							diff = 0;
						}
					}
					else {
						if(frameStart[i] && bytesInDSTBuffer) {
							ret = DSTDecoderDecode(dstDecoder, dstBuffer, buffer+bytesInBuffer, 0, &bytesInDSTBuffer);
							bytesInBuffer += 588*2*8;
							bytesInDSTBuffer = 0;
							if(bytesInBuffer <= diff) {
								diff -= bytesInBuffer;
								bytesInBuffer = 0;
							}
							else {
								memmove(buffer,buffer+diff,bytesInBuffer-diff);
								bytesInBuffer -= diff;
								diff = 0;
							}
						}
						ret = fread(dstBuffer+bytesInDSTBuffer,1,packetLength[i],fp);
						bytesInDSTBuffer += ret;
					}
				}
				else fseeko(fp,packetLength[i],SEEK_CUR);
			}
			else fseeko(fp,packetLength[i],SEEK_CUR);
		}
		fseeko(fp, sectorBegin+2048, SEEK_SET);
		currentLSN++;
		if(mustRead && !diff) break;
	end:
		;
	}
	
	return YES;
}

- (xldoffset_t)totalDSDSamples
{
	return totalSamples;
}

- (void)closeFile
{
	if(fp) fclose(fp);
	fp = nil;
}

- (NSMutableArray *)trackList
{
	return trackList;
}

@end
