//
//  XLDSecureRipperEngine.m
//  XLD
//
//  Created by tmkk on 10/11/13.
//  Copyright 2010 tmkk. All rights reserved.
//

#import "XLDSecureRipperEngine.h"
#import <openssl/md5.h>

#define LOG_RIPPING_STATUS 0

#define OVERLAP 3
/* SECTOR_READ should be large enough to kill a chace on most drives */
#define SECTOR_READ 600
#define SLOWDOWN_THREASHOLD 10
#define ACCEPTED_MATCH 8

#define BAIL_IF_ERR(ret) \
	if(ret < 0) {\
		err |= XLDSecureRipperReadErr;\
		goto last;\
	}

typedef struct _sectorBuffer
{
	unsigned char md5[16];
	int matchCount;
	unsigned char buffer[2352];
	struct _sectorBuffer *next;
} sectorBuffer;

static sectorBuffer *createSectorBuffer(void *buffer)
{
	MD5_CTX context;
	sectorBuffer *sector = calloc(1,sizeof(sectorBuffer));
	memcpy(sector->buffer, buffer, 2352);
	sector->matchCount = 1;
	MD5_Init (&context);
	MD5_Update (&context, buffer, 2352);
	MD5_Final(sector->md5, &context);
	return sector;
}

static void commitSector(sectorBuffer *sector, void *buffer)
{
	unsigned char md5[16];
	MD5_CTX context;
	MD5_Init (&context);
	MD5_Update (&context, buffer, 2352);
	MD5_Final(md5, &context);
	
	sectorBuffer *current = sector;
	while(1) {
		if(!memcmp(current->md5,md5,16)) {
			current->matchCount++;
			break;
		}
		if(!current->next) {
			current->next = calloc(1,sizeof(sectorBuffer));
			memcpy(current->next->buffer, buffer, 2352);
			current->next->matchCount = 1;
			memcpy(current->next->md5,md5,16);
			break;
		}
		current = current->next;
	}
}

static int largestMatchCount(sectorBuffer *sector)
{
	int ret = 0;
	while(sector) {
		if(ret < sector->matchCount) ret = sector->matchCount;
		sector = sector->next;
	}
	return ret;
}

static void readMaximumLikelihoodSector(sectorBuffer *sector, void *buffer)
{
	int match = largestMatchCount(sector);
	while(sector) {
		if(sector->matchCount == match) {
			memcpy(buffer,sector->buffer,2352);
			break;
		}
		sector = sector->next;
	}
}

static void freeSectorBuffer(sectorBuffer *sector)
{
	if(sector->next) freeSectorBuffer(sector->next);
	free(sector);
}

static int countSectorMismatch(void *sector1, void *sector2)
{
	int i;
	int count = 0;
	int *ptr1 = sector1;
	int *ptr2 = sector2;
	for(i=0;i<588;i++) {
		if(*ptr1++ != *ptr2++) count++;
	}
	return count;
}

static int xld_cdda_read_wrapper(xld_cdread_t *disc, void *buffer, int beginLSN, int nSectors, BOOL useC2)
{
	int retry = 0;
	int ret;
	do {
		if(useC2) ret = xld_cdda_read_with_c2(disc, buffer, beginLSN, nSectors);
		else ret = xld_cdda_read(disc, buffer, beginLSN, nSectors);
		if(ret >= 0) break;
	} while(++retry < 20);
	return ret;
}

@implementation XLDSecureRipperEngine

- (id)init
{
	[super init];
	firstReadBufRaw = malloc((2352+294)*(SECTOR_READ+OVERLAP));
	firstReadBuf = firstReadBufRaw + (2352+294)*OVERLAP;
	secondReadBuf = malloc((2352+294)*SECTOR_READ);
	overlapBuffer = malloc((2352+294)*OVERLAP);
	zeroSector = calloc(1,2352);
	bufferedSectorBegin = -1;
	maxRetryCount = 20;
	return self;
}

- (id)initWithReader:(xld_cdread_t *)reader
{
	[self init];
	cdread = reader;
	return self;
}

- (void)dealloc
{
	free(firstReadBufRaw);
	free(secondReadBuf);
	free(overlapBuffer);
	free(zeroSector);
	if(verified) free(verified);
	[super dealloc];
}

- (void *)readSectorWithoutC2:(XLDSecureRipperResult *)result
{
	int err = XLDSecureRipperNoErr;
	int retry,i,mismatchCount,read;
	sectorBuffer *sector = NULL;
		
	//NSLog(@"current: %d",currentLSN);
	
	/* 1st read is not yet completed */
	if(bufferedSectorBegin < 0 || bufferedSectorBegin + bufferedSectorSize <= currentLSN) {
		int required = SECTOR_READ;
		
		if(bufferedSectorBegin >= 0 && currentLSN - OVERLAP >= bufferedSectorBegin) {
			memcpy(overlapBuffer,firstReadBuf+2352*(currentLSN - OVERLAP - bufferedSectorBegin), 2352*OVERLAP);
			overlapBufferIsValid = YES;
		}
		/* continuous read; no need to abuse seeking... */
		else {
			jitterDetect = NO;
		}
		
		if(currentLSN+required > xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN))+1) {
			required = xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN))+1-currentLSN;
		}
		if(jitterDetect) {
			for(retry=0;retry<=maxRetryCount;retry++) {
				mismatchCount = 0;
				read = xld_cdda_read_wrapper(cdread, firstReadBuf-2352*OVERLAP, currentLSN-OVERLAP, OVERLAP, NO);
				BAIL_IF_ERR(read);
				bufferedSectorSize = xld_cdda_read_wrapper(cdread, firstReadBuf, currentLSN, required/2, NO);
				BAIL_IF_ERR(bufferedSectorSize);
				for(i=0;i<OVERLAP;i++) {
					if(memcmp(overlapBuffer+2352*i,firstReadBuf+2352*(i-OVERLAP),2352)) mismatchCount++;
					/*int currentMismatch = countSectorMismatch(overlapBuffer+2352*i,firstReadBuf+2352*(i-OVERLAP));
					if(currentMismatch > 10) mismatchCount++;*/
				}
				if(mismatchCount < OVERLAP) break;
				else if(retry >= SLOWDOWN_THREASHOLD) {
					xld_cdda_speed_set(cdread, 1);
				}
			}
			if(retry > 0) {
				if(retry >= SLOWDOWN_THREASHOLD) xld_cdda_speed_set(cdread, -1);
#if LOG_RIPPING_STATUS
				NSLog(@"1st read: jitter error detected at sector %d, but reduced to %d with %d retry",currentLSN,mismatchCount,retry);
#endif
				err |= XLDSecureRipperJitterErr;
			}
		}
		else {
			bufferedSectorSize = xld_cdda_read_wrapper(cdread, firstReadBuf, currentLSN, required/2, NO);
			BAIL_IF_ERR(bufferedSectorSize);
		}
		if(bufferedSectorSize < required) {
			read = xld_cdda_read_wrapper(cdread, firstReadBuf+2352*bufferedSectorSize, currentLSN+bufferedSectorSize, required-bufferedSectorSize, NO);
			BAIL_IF_ERR(read);
			bufferedSectorSize += read;
		}
		
		//NSLog(@"reading %d sectors from %d, return %d",required,currentLSN,bufferedSectorSize);
		bufferedSectorBegin = currentLSN;
		if(verified) free(verified);
		verified = calloc(sizeof(BOOL), required);
		for(retry=0;retry<=maxRetryCount;retry++) {
			mismatchCount = 0;
			read = xld_cdda_read_wrapper(cdread, secondReadBuf, currentLSN, required/2, NO);
			BAIL_IF_ERR(read);
			if(read < required) {
				int ret = xld_cdda_read_wrapper(cdread, secondReadBuf+2352*read, currentLSN+read, required-read, NO);
				BAIL_IF_ERR(ret);
				read += ret;
			}
			for(i=0;i<read;i++) {
#if 1
				if(!memcmp(firstReadBuf+2352*i,secondReadBuf+2352*i,2352)) verified[i] = YES;
				else {
					verified[i] = NO;
					mismatchCount++;
				}
#else
				int currentMismatch = countSectorMismatch(firstReadBuf+2352*i,secondReadBuf+2352*i);
				if(currentMismatch == 0) verified[i] = YES;
				else {
					verified[i] = NO;
					if(currentMismatch > 10) mismatchCount++;
				}
#endif
			}
			if(mismatchCount < read/2) break;
			else if(retry >= SLOWDOWN_THREASHOLD) {
				xld_cdda_speed_set(cdread, 1);
			}
		}
		if(retry > 0) {
			if(retry >= SLOWDOWN_THREASHOLD) xld_cdda_speed_set(cdread, -1);
#if LOG_RIPPING_STATUS
			NSLog(@"2nd read: jitter error detected at sector %d, but reduced to %d with %d retry ",currentLSN,mismatchCount,retry);
#endif
			err |= XLDSecureRipperJitterErr;
		}
		jitterDetect = NO;
	}
	
	/* retry read */
	if(!verified[currentLSN-bufferedSectorBegin]) {
#if LOG_RIPPING_STATUS
		NSLog(@"sector mismatch @ %d, retrying",currentLSN);
#endif
		sector = createSectorBuffer(firstReadBuf+2352*(currentLSN-bufferedSectorBegin));
		commitSector(sector, secondReadBuf+2352*(currentLSN-bufferedSectorBegin));
		for(retry = 0; retry <= maxRetryCount; retry++) {
			if(currentLSN > 0 && overlapBufferIsValid) {
				/* check jitter... */
				for(i=0;i<=maxRetryCount;i++) {
					read = xld_cdda_read_wrapper(cdread, secondReadBuf, currentLSN-1, 1, NO);
					BAIL_IF_ERR(read);
					read = xld_cdda_read_wrapper(cdread, secondReadBuf+2352, currentLSN, 1, NO);
					BAIL_IF_ERR(read);
					if(currentLSN == bufferedSectorBegin) {
						/* we are at the top of the buffered sector, so compare with the overlap buffer */
						mismatchCount = countSectorMismatch(overlapBuffer+2352*(OVERLAP-1),secondReadBuf);
					}
					else {
						/* simply compare with the previous sector in the buffer */
						mismatchCount = countSectorMismatch(firstReadBuf+2352*(currentLSN - bufferedSectorBegin - 1),secondReadBuf);
					}
					if(mismatchCount < 588/2) break;
					else if(i >= SLOWDOWN_THREASHOLD) {
						xld_cdda_speed_set(cdread, 1);
					}
					/* flush cache */
					{
						int flushSeekPos = currentLSN + SECTOR_READ;
						if(flushSeekPos > xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN)))
							flushSeekPos = xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN));
						read = xld_cdda_read_wrapper(cdread, secondReadBuf, flushSeekPos, 1, NO);
						BAIL_IF_ERR(read);
					}
				}
				if(i > 0) {
					//if(retry <= maxRetryCount/2 && i > maxRetryCount/2) xld_cdda_speed_set(cdread, -1);
#if LOG_RIPPING_STATUS
					NSLog(@"re-read: jitter error detected, but reduced to %d with %d retry ",mismatchCount,i);
#endif
					err |= XLDSecureRipperJitterErr;
				}
				commitSector(sector, secondReadBuf+2352);
			}
			else {
				read = xld_cdda_read_wrapper(cdread, secondReadBuf, currentLSN, 1, NO);
				BAIL_IF_ERR(read);
				commitSector(sector, secondReadBuf);
				if(currentLSN < xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN))) {
					read = xld_cdda_read_wrapper(cdread, secondReadBuf, currentLSN+1, 1, NO);
					BAIL_IF_ERR(read);
				}
			}
			if(largestMatchCount(sector) >= ACCEPTED_MATCH) {
				verified[currentLSN-bufferedSectorBegin] = YES;
				break;
			}
			else if(retry >= SLOWDOWN_THREASHOLD) {
				xld_cdda_speed_set(cdread, 1);
			}
			/* flush cache */
			{
				int flushSeekPos = currentLSN + SECTOR_READ;
				if(flushSeekPos > xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN)))
					flushSeekPos = xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN));
				read = xld_cdda_read_wrapper(cdread, secondReadBuf, flushSeekPos, 1, NO);
				BAIL_IF_ERR(read);
			}
		}
		xld_cdda_speed_set(cdread, -1);
		if(verified[currentLSN-bufferedSectorBegin]) {
			err |= XLDSecureRipperRetry;
#if LOG_RIPPING_STATUS
			NSLog(@"retry success (%d)",retry);
#endif
		}
		else {
			err |= XLDSecureRipperDamaged;
#if LOG_RIPPING_STATUS
			NSLog(@"retry failure with %d match",largestMatchCount(sector));
#endif
		}
		readMaximumLikelihoodSector(sector,firstReadBuf+2352*(currentLSN-bufferedSectorBegin));
		jitterDetect = YES;
	}
last:
	if(sector) freeSectorBuffer(sector);
	if(result) *result = err;
	if(err & XLDSecureRipperReadErr) {
		bufferedSectorBegin = -1;
		bufferedSectorSize = 0;
		jitterDetect = NO;
		overlapBufferIsValid = NO;
		currentLSN++;
		return zeroSector;
	}
	return firstReadBuf+2352*(currentLSN++ - bufferedSectorBegin);
}

- (void *)readSectorWithC2:(XLDSecureRipperResult *)result
{
	int retry,i,j,mismatchCount,read;
	int err = XLDSecureRipperNoErr;
	sectorBuffer *sector = NULL;
	
	//NSLog(@"current: %d",currentLSN);
	if(bufferedSectorBegin < 0 || bufferedSectorBegin + bufferedSectorSize <= currentLSN) {
		int required = SECTOR_READ;
		
		if(bufferedSectorBegin >= 0 && currentLSN - OVERLAP >= bufferedSectorBegin) {
			memcpy(overlapBuffer,firstReadBuf+(2352+294)*(currentLSN - OVERLAP - bufferedSectorBegin), (2352+294)*OVERLAP);
			overlapBufferIsValid = YES;
		}
		/* continuous read; no need to abuse seeking... */
		else {
			jitterDetect = NO;
		}
		
		if(currentLSN+required > xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN))+1) {
			required = xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN))+1-currentLSN;
		}
		if(jitterDetect) {
			for(retry=0;retry<=maxRetryCount;retry++) {
				mismatchCount = 0;
				read = xld_cdda_read_wrapper(cdread, firstReadBuf-(2352+294)*OVERLAP, currentLSN-OVERLAP, OVERLAP, YES);
				BAIL_IF_ERR(read);
				bufferedSectorSize = xld_cdda_read_wrapper(cdread, firstReadBuf, currentLSN, required/2, YES);
				BAIL_IF_ERR(bufferedSectorSize);
				for(i=0;i<OVERLAP;i++) {
					if(memcmp(overlapBuffer+(2352+294)*i,firstReadBuf+(2352+294)*(i-OVERLAP),2352)) mismatchCount++;
				}
				if(mismatchCount < OVERLAP) break;
				else if(retry >= SLOWDOWN_THREASHOLD) {
					xld_cdda_speed_set(cdread, 1);
				}
			}
			if(retry > 0) {
				if(retry >= SLOWDOWN_THREASHOLD) xld_cdda_speed_set(cdread, -1);
#if LOG_RIPPING_STATUS
				NSLog(@"1st read: jitter error detected at sector %d, but reduced to %d with %d retry",currentLSN,mismatchCount,retry);
#endif
				err |= XLDSecureRipperJitterErr;
			}
		}
		else {
			bufferedSectorSize = xld_cdda_read_wrapper(cdread, firstReadBuf, currentLSN, required/2, YES);
			BAIL_IF_ERR(bufferedSectorSize);
		}
		if(bufferedSectorSize < required) {
			read = xld_cdda_read_wrapper(cdread, firstReadBuf+(2352+294)*bufferedSectorSize, currentLSN+bufferedSectorSize, required-bufferedSectorSize, YES);
			BAIL_IF_ERR(read);
			bufferedSectorSize += read;
		}
		
		//NSLog(@"reading %d sectors from %d, return %d",required,currentLSN,bufferedSectorSize);
		bufferedSectorBegin = currentLSN;
		if(verified) free(verified);
		verified = calloc(sizeof(BOOL), required);
		for(i=0;i<bufferedSectorSize;i++) {
			for(j=0;j<294;j++) {
				if(firstReadBuf[(2352+294)*i+2352+j]) break;
			}
			if(j==294) verified[i] = YES;
			else verified[i] = NO;
		}
		jitterDetect = NO;
	}
	
	if(!verified[currentLSN-bufferedSectorBegin]) {
#if LOG_RIPPING_STATUS
		NSLog(@"sector mismatch @ %d, retrying",currentLSN);
#endif
		sector = createSectorBuffer(firstReadBuf+(2352+294)*(currentLSN-bufferedSectorBegin));
		for(retry = 0; retry <= maxRetryCount; retry++) {
			if(currentLSN > 0 && overlapBufferIsValid) {
				/* check jitter... */
				for(i=0;i<=maxRetryCount;i++) {
					read = xld_cdda_read_wrapper(cdread, secondReadBuf, currentLSN-1, 1, NO); /* read previous sector without c2; for jitter check */
					BAIL_IF_ERR(read);
					read = xld_cdda_read_wrapper(cdread, secondReadBuf+2352, currentLSN, 1, YES);
					BAIL_IF_ERR(read);
					if(currentLSN == bufferedSectorBegin) {
						/* we are at the top of the buffered sector, so compare with the overlap buffer */
						mismatchCount = countSectorMismatch(overlapBuffer+(2352+294)*(OVERLAP-1),secondReadBuf);
					}
					else {
						/* simply compare with the previous sector in the buffer */
						mismatchCount = countSectorMismatch(firstReadBuf+(2352+294)*(currentLSN - bufferedSectorBegin - 1),secondReadBuf);
					}
					if(mismatchCount < 588/2) break;
					else if(i >= SLOWDOWN_THREASHOLD) {
						xld_cdda_speed_set(cdread, 1);
					}
					/* flush cache */
					{
						int flushSeekPos = currentLSN + SECTOR_READ;
						if(flushSeekPos > xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN)))
							flushSeekPos = xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN));
						read = xld_cdda_read_wrapper(cdread, secondReadBuf, flushSeekPos, 1, NO);
						BAIL_IF_ERR(read);
					}
				}
				if(i > 0) {
#if LOG_RIPPING_STATUS
					NSLog(@"re-read: jitter error detected, but reduced to %d with %d retry ",mismatchCount,i);
#endif
					err |= XLDSecureRipperJitterErr;
				}
				commitSector(sector, secondReadBuf+2352);
				memmove(secondReadBuf, secondReadBuf+2352, 2352+294);
			}
			else {
				read = xld_cdda_read_wrapper(cdread, secondReadBuf, currentLSN, 1, YES);
				BAIL_IF_ERR(read);
				commitSector(sector, secondReadBuf);
				if(currentLSN < xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN))) {
					read = xld_cdda_read_wrapper(cdread, secondReadBuf+2352+294, currentLSN+1, 1, NO);
					BAIL_IF_ERR(read);
				}
			}
			
			for(j=0;j<294;j++) {
				if(secondReadBuf[2352+j]) break;
			}
			if(j==294) {
				verified[currentLSN-bufferedSectorBegin] = YES;
				break;
			}
			else if(retry >= SLOWDOWN_THREASHOLD) {
				xld_cdda_speed_set(cdread, 1);
			}
			/* flush cache */
			{
				int flushSeekPos = currentLSN + SECTOR_READ;
				if(flushSeekPos > xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN)))
					flushSeekPos = xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN));
				read = xld_cdda_read_wrapper(cdread, secondReadBuf, flushSeekPos, 1, NO);
				BAIL_IF_ERR(read);
			}
		}
		xld_cdda_speed_set(cdread, -1);
		if(verified[currentLSN-bufferedSectorBegin]) {
			memcpy(firstReadBuf+(2352+294)*(currentLSN-bufferedSectorBegin),secondReadBuf,2352);
			err |= XLDSecureRipperRetry;
#if LOG_RIPPING_STATUS
			NSLog(@"retry success (%d)",retry);
#endif
		}
		else {
#if LOG_RIPPING_STATUS
			NSLog(@"retry failure with %d match",largestMatchCount(sector));
#endif
			err |= XLDSecureRipperDamaged;
			readMaximumLikelihoodSector(sector,firstReadBuf+(2352+294)*(currentLSN-bufferedSectorBegin));
		}
		jitterDetect = YES;
	}
last:
	if(sector) freeSectorBuffer(sector);
	if(result) *result = err;
	if(err & XLDSecureRipperReadErr) {
		bufferedSectorBegin = -1;
		bufferedSectorSize = 0;
		jitterDetect = NO;
		overlapBufferIsValid = NO;
		currentLSN++;
		return zeroSector;
	}
	return firstReadBuf+(2352+294)*(currentLSN++ - bufferedSectorBegin);
}

- (void *)readSectorWithBurst:(XLDSecureRipperResult *)result
{
	int err = XLDSecureRipperNoErr;
	if(bufferedSectorBegin < 0 || bufferedSectorBegin + bufferedSectorSize <= currentLSN) {
		int required = SECTOR_READ;
		
		if(currentLSN+required > xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN))+1) {
			required = xld_cdda_disc_lastsector_currentsession(cdread, xld_cdda_sector_getsession(cdread,currentLSN))+1-currentLSN;
		}
		bufferedSectorSize = xld_cdda_read_wrapper(cdread, firstReadBuf, currentLSN, required, NO);
		BAIL_IF_ERR(bufferedSectorSize);
		bufferedSectorBegin = currentLSN;
	}
last:
	if(result) *result = err;
	if(err & XLDSecureRipperReadErr) {
		bufferedSectorBegin = -1;
		bufferedSectorSize = 0;
		jitterDetect = NO;
		overlapBufferIsValid = NO;
		currentLSN++;
		return zeroSector;
	}
	return firstReadBuf+2352*(currentLSN++ - bufferedSectorBegin);
}

- (void *)readSector:(XLDSecureRipperResult *)result
{
	if(ripperMode == kRipperModeBurst) return [self readSectorWithBurst:result];
	else if(ripperMode == (kRipperModeXLD|kRipperModeC2)) return [self readSectorWithC2:result];
	else return [self readSectorWithoutC2:result];
}

- (void)seekToSector:(int)sector
{
	currentLSN = sector;
	bufferedSectorBegin = -1;
	bufferedSectorSize = 0;
	jitterDetect = NO;
	overlapBufferIsValid = NO;
}

- (void)setMaxRetryCount:(int)count
{
	maxRetryCount = count;
}

- (void)setRipperMode:(XLDRipperMode)mode
{
	bufferedSectorBegin = -1;
	bufferedSectorSize = 0;
	jitterDetect = NO;
	overlapBufferIsValid = NO;
	ripperMode = mode;
}

@end
