//
//  XLDCDDABackend.c
//  XLD
//
//  Created by tmkk on 10/11/9.
//  Copyright 2010 tmkk. All rights reserved.
//

#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOCDMedia.h>
#include <IOKit/storage/IOCDTypes.h>
#include <IOKit/storage/IOCDMediaBSDClient.h>
#include <IOKit/scsi/IOSCSIMultimediaCommandsDevice.h>
#include <CoreFoundation/CoreFoundation.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include "XLDCDDABackend.h"

#define C2READ_PER_LOOP 40

static char isrc2Ascii(unsigned char c)
{
	if (c <= 9)
		return '0' + c;
	
	if (c >= 17 && c <= 42)
		return 'A' + (c - 17);
	
	return 0;
}

static void print_info(xld_cdread_t *disc)
{
	fprintf(stderr,"Drive: %s %s %s\n",disc->vendor,disc->product,disc->revision);
	fprintf(stderr,"Number of sessions: %d\n",disc->numSessions);
	fprintf(stderr,"Number of tracks: %d\n",disc->numTracks);
	int i;
	for(i=0;i<disc->numTracks;i++) {
		fprintf(stderr,"Track %02d (session %d)\n",i+1,disc->tracks[i].session);
		if(disc->tracks[i].type == kTrackTypeAudio) {
			if(disc->tracks[i].preEmphasis) fprintf(stderr,"  Audio with pre-emphasis\n");
			else fprintf(stderr,"  Audio\n");
		}
		else fprintf(stderr,"  Data\n");
		CDMSF msf = CDConvertLBAToMSF(disc->tracks[i].start/588);
		fprintf(stderr,"  start : %02d:%02d:%02d (%d)\n",msf.minute,msf.second,msf.frame,disc->tracks[i].start/588);
		msf = CDConvertLBAToMSF(disc->tracks[i].length/588-150);
		fprintf(stderr,"  length: %02d:%02d:%02d\n",msf.minute,msf.second,msf.frame);
	}
}

static CDTOC *read_toc_with_iokit(xld_cdread_t *disc)
{
	io_service_t  service;
	io_iterator_t service_iterator;
	CFMutableDictionaryRef properties = NULL;
	CFDataRef data;
	CDTOC *toc = NULL;
	IOServiceGetMatchingServices(kIOMasterPortDefault, IOBSDNameMatching(kIOMasterPortDefault,0,strrchr(disc->device,'/')+1), &service_iterator);
	service = IOIteratorNext(service_iterator);
	if(!service) {
		IOObjectRelease(service_iterator);
		return NULL;
	}
	IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0);
	if(!properties) goto last;
	data = (CFDataRef)CFDictionaryGetValue(properties, CFSTR(kIOCDMediaTOCKey));
	if(!data) goto last;
	toc = malloc(CFDataGetLength(data));
	CFDataGetBytes(data, CFRangeMake(0, CFDataGetLength(data)), (UInt8 *)toc);
	
last: 
	if(properties) CFRelease(properties);
	IOObjectRelease(service);
	IOObjectRelease(service_iterator);
	return toc;
}

static int read_disc_info(xld_cdread_t *disc)
{
	dk_cd_read_disc_info_t discinforead;
	CDDiscInfo *info = calloc(1,sizeof(CDDiscInfo));
	memset(&discinforead,0, sizeof(discinforead));
	discinforead.bufferLength = sizeof(CDDiscInfo);
	discinforead.buffer = info;
	int ret = ioctl(disc->fd, DKIOCCDREADDISCINFO, &discinforead);
	if(ret < 0) {
		perror("DKIOCCDREADDISCINFO(1) failure");
	}
	fprintf(stderr,"barcode:%d, status:%d\n",info->discBarCodeValid,info->discStatus);
	return 0;
}

static int read_toc(xld_cdread_t *disc)
{
#if 0
	dk_cd_read_toc_t tocread;
	CDTOC *toc = calloc(1,sizeof(CDTOC));
	memset(&tocread,0, sizeof(tocread));
	tocread.format = kCDTOCFormatTOC;
	tocread.bufferLength = sizeof(CDTOC);
	tocread.buffer = toc;
	int ret = ioctl(disc->fd, DKIOCCDREADTOC, &tocread);
	if(ret < 0) {
		perror("DKIOCCDREADTOC(1) failure");
		goto fallback;
	}
	
	/* 1st try; read with returned descriptor size */
	int size = OSSwapBigToHostInt16(toc->length)+sizeof(toc->length);
	free(toc);
	toc = calloc(1,size);
	memset(&tocread,0, sizeof(tocread));
	tocread.format = kCDTOCFormatTOC;
	tocread.bufferLength = size;
	tocread.buffer = toc;
	ret = ioctl(disc->fd, DKIOCCDREADTOC, &tocread);
	if(ret < 0) {
		perror("DKIOCCDREADTOC(2) failure");
	fallback:
		/* 2nd try; read with sufficient buffer size */
		size = sizeof(CDTOCDescriptor)*120+sizeof(CDTOC);
		free(toc);
		toc = calloc(1,size);
		memset(&tocread,0, sizeof(tocread));
		tocread.format = kCDTOCFormatTOC;
		tocread.bufferLength = size;
		tocread.buffer = toc;
		ret = ioctl(disc->fd, DKIOCCDREADTOC, &tocread);
		if(ret < 0) {
			perror("DKIOCCDREADTOC(3) failure");
			free(toc);
			/* final fallback... */
			toc = read_toc_with_iokit(disc);
			if(!toc) {
				fprintf(stderr,"reading TOC with IOKit failed\n");
				return -1;
			}
		}
	}
#else
	CDTOC *toc = read_toc_with_iokit(disc);
	if(!toc) {
		fprintf(stderr,"reading TOC with IOKit failed\n");
		return -1;
	}
#endif
	
	int descCount = CDTOCGetDescriptorCount(toc);
	int i;
	int nextStart = 0;
	disc->numTracks = 0;
	disc->numSessions = toc->sessionLast;
	for(i=0;i<descCount;i++) {
		int tno = toc->descriptors[i].point;
		int adr = toc->descriptors[i].adr;
		if(tno == 0xa1 && adr == 1) {
			disc->numTracks = toc->descriptors[i].p.minute;
		}
		else if(tno == 0xa2 && adr == 1) {
			nextStart = 588*CDConvertMSFToLBA(toc->descriptors[i].p);
		}
	}
	if(!disc->numTracks) { //fallback
		for(i=0;i<descCount;i++) {
			int tno = toc->descriptors[i].point;
			int adr = toc->descriptors[i].adr;
			if(tno > 0 && tno < 100 && adr == 1)
				disc->numTracks++;
		}
	}
	if(!disc->numTracks) {
		fprintf(stderr,"Error: no tracks found\n");
		free(toc);
		return -1;
	}
	disc->tracks = calloc(1,sizeof(xld_track_t)*disc->numTracks);
	for(i=0;i<descCount;i++) {
		int tno = toc->descriptors[i].point;
		int adr = toc->descriptors[i].adr;
		if(tno > 0 && tno <= disc->numTracks && adr == 1) {
			disc->tracks[tno-1].start = 588*CDConvertMSFToLBA(toc->descriptors[i].p);
			disc->tracks[tno-1].session = toc->descriptors[i].session;
			disc->tracks[tno-1].type = toc->descriptors[i].control & 0x4 ? kTrackTypeData : kTrackTypeAudio;
			disc->tracks[tno-1].preEmphasis = disc->tracks[tno-1].type == kTrackTypeData ? 0 : (toc->descriptors[i].control & 0x1 ? 1 : 0);
			disc->tracks[tno-1].dcp = (toc->descriptors[i].control & 0x2) ? 1 : 0;
		}
	}
	if(!nextStart) {
		fprintf(stderr,"Error: leadout not found\n");
		free(toc);
		free(disc->tracks);
		disc->tracks = NULL;
		return -1;
	}
	for(i=disc->numTracks-1;i>=0;i--) {
		disc->tracks[i].length = nextStart - disc->tracks[i].start;
		nextStart = disc->tracks[i].start;
		if(i<disc->numTracks-1 && disc->tracks[i].session != disc->tracks[i+1].session) {
			/* first additional session : 11250 sectors lead-out/in + 150 sectors pregap */
			if(disc->tracks[i].session == 1) disc->tracks[i].length -= 588*11400;
			/* further additional sessions : 6750 sectors lead-out/in + 150 sectors pregap */
			else disc->tracks[i].length -= 588*6900;
		}
	}
	
	if(disc->tracks[0].start != 0) disc->tracks[0].pregap = disc->tracks[0].start;

	free(toc);
	return 0;
}

static int is_recordable_media(xld_cdread_t *disc)
{
	dk_cd_read_toc_t cdTOC;
	CDATIP* atipData = (CDATIP *)calloc(1,sizeof(CDATIP));
	atipData->dataLength = sizeof(CDATIP);
	
	bzero((void *)&cdTOC, sizeof(dk_cd_read_toc_t));
	cdTOC.format = kCDTOCFormatATIP;
	cdTOC.formatAsTime = 0;
	cdTOC.address.track = 0;
	cdTOC.bufferLength = sizeof(CDATIP);
	cdTOC.buffer = atipData;
	
	if(ioctl(disc->fd, DKIOCCDREADTOC, &cdTOC) != -1) {
		fprintf(stderr,"ATIP:\n");
		fprintf(stderr," dataLength: %d\n", atipData->dataLength);
		fprintf(stderr," discType: 0x%02x\n", atipData->discType);
		fprintf(stderr," discSubtype: 0x%02x\n", atipData->discSubType);
		fprintf(stderr," ATIP Lead-in: %02d:%02d:%02d\n", atipData->startTimeOfLeadIn.minute,atipData->startTimeOfLeadIn.second,atipData->startTimeOfLeadIn.frame);
		free(atipData);
		return 1;
	}
	else {
		fprintf(stderr,"Not a CD-R/RW media.\n");
	}
	free(atipData);
	return 0;
}

static void read_hw_info(xld_cdread_t *disc)
{
	io_service_t  service;
	io_iterator_t service_iterator;
	char servicePath1[1024],servicePath2[1024];
	IOServiceGetMatchingServices(kIOMasterPortDefault, IOBSDNameMatching(kIOMasterPortDefault,0,strrchr(disc->device,'/')+1), &service_iterator);
	service = IOIteratorNext(service_iterator);
	if(!service) {
		IOObjectRelease(service_iterator);
		return;
	}
	IORegistryEntryGetPath(service, kIOServicePlane, servicePath1);
	IOObjectRelease(service);
	IOObjectRelease(service_iterator);
	
	IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOCDBlockStorageDevice"), &service_iterator);
	while((service = IOIteratorNext(service_iterator)) != 0) {
		IORegistryEntryGetPath(service, kIOServicePlane, servicePath2);
		if(strncmp(servicePath1,servicePath2,strlen(servicePath2))) {
			IOObjectRelease(service);
			continue;
		}
		CFMutableDictionaryRef properties;
		IORegistryEntryCreateCFProperties (service, &properties, kCFAllocatorDefault, 0);
		CFDictionaryRef deviceDict = (CFDictionaryRef)CFDictionaryGetValue(properties, CFSTR(kIOPropertyDeviceCharacteristicsKey));
		CFStringRef vendor   = NULL;
		CFStringRef product  = NULL;
		CFStringRef revision = NULL;
		if(deviceDict) {
			vendor = (CFStringRef)CFDictionaryGetValue(deviceDict, CFSTR(kIOPropertyVendorNameKey));
			product = (CFStringRef)CFDictionaryGetValue(deviceDict, CFSTR(kIOPropertyProductNameKey));
			revision = (CFStringRef)CFDictionaryGetValue(deviceDict, CFSTR(kIOPropertyProductRevisionLevelKey));
		}
		else fprintf(stderr,"deviceDict is NULL\n");
		if(vendor) {
			int length = CFStringGetLength(vendor)+1;
			disc->vendor = malloc(length);
			CFStringGetCString(vendor,disc->vendor,length,kCFStringEncodingUTF8);
		}
		if(product) {
			int length = CFStringGetLength(product)+1;
			disc->product = malloc(length);
			CFStringGetCString(product,disc->product,length,kCFStringEncodingUTF8);
		}
		if(revision) {
			int length = CFStringGetLength(revision)+1;
			disc->revision = malloc(length);
			CFStringGetCString(revision,disc->revision,length,kCFStringEncodingUTF8);
		}
		CFRelease(properties);
		IOObjectRelease(service);
		break;
	}
	
	IOObjectRelease(service_iterator);
}

int xld_cdda_open(xld_cdread_t *disc, char *device)
{
	memset(disc, 0, sizeof(xld_cdread_t));
	disc->fd = open(device, O_RDONLY);
	if(disc->fd < 0) {
		perror("open failed");
		disc->fd = open(device, O_RDONLY|O_NONBLOCK);
		if(disc->fd < 0) {
			perror("open failed");
			return -1;
		}
	}
	disc->device = malloc(strlen(device)+1);
	strcpy(disc->device,device);
	if(read_toc(disc) < 0) {
		close(disc->fd);
		free(disc->device);
		disc->device = NULL;
		return -1;
	}
	disc->opened = 1;
	disc->nsectors = 8;
	read_hw_info(disc);
	xld_cdda_speed_set(disc,-1);
	//read_disc_info(disc);
	//is_recordable_media(disc);
	//print_info(disc);
	return 0;
}

void xld_cdda_close(xld_cdread_t *disc)
{
	if(!disc->opened) return;
	xld_cdda_set_max_speed(disc, -1);
	if(disc->device) free(disc->device);
	if(disc->tracks) free(disc->tracks);
	if(disc->vendor) free(disc->vendor);
	if(disc->product) free(disc->product);
	if(disc->revision) free(disc->revision);
	close(disc->fd);
	memset(disc, 0, sizeof(xld_cdread_t));
}

int xld_cdda_read_timed(xld_cdread_t *disc, void *buffer, int beginLSN, int nSectors, int *ms)
{
	dk_cd_read_t cdread;
	struct timeval tv1, tv2;
	memset(&cdread, 0, sizeof(cdread));
	cdread.sectorArea = kCDSectorAreaUser;
	cdread.sectorType = kCDSectorTypeCDDA;
	cdread.offset = beginLSN * 2352;
	cdread.bufferLength = 2352*nSectors;
	cdread.buffer = buffer;
	
	if(xld_cdda_sector_gettrack(disc,beginLSN) == -1) {
		//fprintf(stderr,"warning: trying to read lead-out from %d\n",beginLSN);
		memset(buffer,0,2352*nSectors);
		if(ms) *ms = 0;
		return -1;
	}
	else if(xld_cdda_sector_gettrack(disc,beginLSN+nSectors-1) == -1) {
		//fprintf(stderr,"warning: trying to read into lead-out from %d\n",beginLSN);
		cdread.bufferLength = 2352*(xld_cdda_track_lastsector(disc,xld_cdda_sector_gettrack(disc,beginLSN))+1-beginLSN);
	}
	gettimeofday(&tv1,NULL);
	int ret = ioctl(disc->fd, DKIOCCDREAD, &cdread);
	gettimeofday(&tv2,NULL);
	if(ms) {
		*ms = (tv2.tv_sec - tv1.tv_sec)*1000 + (tv2.tv_usec - tv1.tv_usec)/1000;
	}
	if(ret < 0) {
		perror("read error");
		return -1;
	}
	if(xld_cdda_sector_gettrack(disc,beginLSN+nSectors-1) == -1) {
		memset((char *)(cdread.buffer)+cdread.bufferLength,0,2352*nSectors - cdread.bufferLength);
		//cdread.bufferLength = 2352*nSectors;
	}
#ifdef _BIG_ENDIAN
	unsigned char *buf = buffer;
	unsigned char tmp;
	int i;
	for(i=0;i<cdread.bufferLength;i+=2) {
		tmp = buf[i+1];
		buf[i+1] = buf[i];
		buf[i] = tmp;
	}
#endif
	
	return cdread.bufferLength/2352;
}

int xld_cdda_read(xld_cdread_t *disc, void *buffer, int beginLSN, int nSectors)
{
	return xld_cdda_read_timed(disc,buffer,beginLSN,nSectors,NULL);
}

int xld_cdda_read_with_c2(xld_cdread_t *disc, void *buffer, int beginLSN, int nSectors)
{
	int sectorsToRead = nSectors;
	int sectorsDone = 0;
	dk_cd_read_t cdread;
	
	if(xld_cdda_sector_gettrack(disc,beginLSN) == -1) {
		//fprintf(stderr,"warning: trying to read lead-out from %d\n",beginLSN);
		memset(buffer,0,(2352+294)*nSectors);
		return -1;
	}
	else if(xld_cdda_sector_gettrack(disc,beginLSN+nSectors-1) == -1) {
		//fprintf(stderr,"warning: trying to read into lead-out from %d\n",beginLSN);
		sectorsToRead = xld_cdda_track_lastsector(disc,xld_cdda_sector_gettrack(disc,beginLSN))+1-beginLSN;
	}
	
	while(sectorsDone < sectorsToRead) {
		int sectorsPerLoop = C2READ_PER_LOOP;
		if(sectorsToRead - sectorsDone < C2READ_PER_LOOP) sectorsPerLoop = sectorsToRead - sectorsDone;
		memset(&cdread, 0, sizeof(cdread));
		cdread.sectorArea = kCDSectorAreaUser | kCDSectorAreaErrorFlags;
		cdread.sectorType = kCDSectorTypeCDDA;
		cdread.offset = (beginLSN+sectorsDone) * (2352+294);
		cdread.bufferLength = (2352+294)*sectorsPerLoop;
		cdread.buffer = (unsigned char *)buffer+sectorsDone*(2352+294);
		
		int ret = ioctl(disc->fd, DKIOCCDREAD, &cdread);
		if(ret < 0) {
			perror("read error");
			return -1;
		}
		sectorsDone += sectorsPerLoop;
	}
	
	if(sectorsDone < nSectors) {
		memset((char *)(cdread.buffer)+(2352+294)*sectorsDone,0,(2352+294)*(nSectors - sectorsDone));
	}
#ifdef _BIG_ENDIAN
	unsigned char *buf = buffer;
	unsigned char tmp;
	int i,j;
	for(i=0;i<sectorsDone;i++) {
		for(j=0;j<2352;j+=2) {
			tmp = buf[i*(2352+294)+j+1];
			buf[i*(2352+294)+j+1] = buf[i*(2352+294)+j];
			buf[i*(2352+294)+j] = tmp;
		}
	}
#endif
	
	return sectorsDone;
}

int xld_cdda_disc_firstsector(xld_cdread_t *disc)
{
	return 0;
}

int xld_cdda_disc_lastsector(xld_cdread_t *disc)
{
	return (disc->tracks[disc->numTracks-1].start + disc->tracks[disc->numTracks-1].length)/588-1;
}

int xld_cdda_disc_lastsector_currentsession(xld_cdread_t *disc, int sector)
{
	int session = 1, i, ret=0;
	for(i=0;i<disc->numTracks;i++) {
		if(sector < disc->tracks[i].start/588) break;
		session = disc->tracks[i].session;
	}
	
	for(i=0;i<disc->numTracks;i++) {
		if(disc->tracks[i].session > session) break;
		ret = (disc->tracks[i].start + disc->tracks[i].length)/588 - 1;
	}
	return ret;
}

int xld_cdda_sector_gettrack(xld_cdread_t *disc, int sector)
{
	//sector -= 150;
	if(sector >= 0 && sector < disc->tracks[0].start) return 0;
	int i;
	for(i=0;i<disc->numTracks;i++) {
		int start = disc->tracks[i].start/588;
		int end = (disc->tracks[i].start + disc->tracks[i].length)/588;
		if(sector >= start && sector < end) return i+1;
	}
	return -1;
}

int xld_cdda_tracks(xld_cdread_t *disc)
{
	return disc->numTracks;
}

int xld_cdda_track_firstsector(xld_cdread_t *disc, int track)
{
	return disc->tracks[track-1].start/588;
}

int xld_cdda_track_lastsector(xld_cdread_t *disc, int track)
{
	return (disc->tracks[track-1].start + disc->tracks[track-1].length)/588-1;
}

int xld_cdda_track_audiop(xld_cdread_t *disc, int track)
{
	return (disc->tracks[track-1].type == kTrackTypeAudio) ? 1 : 0;
}

int xld_cdda_speed_set(xld_cdread_t *disc, int speed)
{
	unsigned short spd;
	if(speed <= 0) spd = disc->maxSpeed ? disc->maxSpeed * kCDSpeedMin : kCDSpeedMax;
	else spd = speed * kCDSpeedMin;
	return ioctl(disc->fd,DKIOCCDSETSPEED,&spd);
}

#define CRCPOLY  0x1021U

static unsigned int calc_crc(int n, unsigned char c[])
{
    unsigned int i, j, r;
	
    r = 0x0000U;
	for (i = 0; i < n; i++) {
		r ^= (unsigned short)c[i] << 8;
		for (j = 0; j < 8; j++) {
            if (r & 0x8000U) r = (r << 1) ^ CRCPOLY;
			else             r <<= 1;
		}
    }
    return ~r & 0xFFFFU;
}

void xld_cdda_read_pregap(xld_cdread_t *disc, int track)
{
	if(track<=1 || track>disc->numTracks || disc->tracks[track-1].type != kTrackTypeAudio || disc->tracks[track-2].type != kTrackTypeAudio) return;
	int state = 0;
	int errorCount = 0;
	int totalErrorCount = 0;
	int pregapLength = 0;
	int success = 0;
	int firstQchannelRead = 1;
	unsigned char *buffer = malloc(2352+16);
	dk_cd_read_t cdread;
	memset(&cdread, 0, sizeof(cdread));
	cdread.sectorArea = kCDSectorAreaUser | kCDSectorAreaSubChannelQ;
	cdread.sectorType = kCDSectorTypeCDDA;
	cdread.bufferLength = 2352+16;
	cdread.buffer = buffer;
	
	/* -------
	 state
	 0 : not a pregap
	 1 : suspicious
	 2 : pregap
	------- */

	int beginOffset = 300; /* 4 sec */
	if(disc->tracks[track-2].length/588 <= 300) {
		beginOffset = disc->tracks[track-2].length/588 - 1;
		firstQchannelRead = 0;
	}
	cdread.offset = (disc->tracks[track-1].start/588-beginOffset)*(2352+16);
	while(1) {
		int result = ioctl(disc->fd, DKIOCCDREAD, &cdread);
		if(result != -1) {
			unsigned int adr = buffer[2352] & 0xf;
			unsigned int crc = buffer[2362]<<8 | buffer[2363];
			if(disc->nonBCD && adr == 0x1) {
				buffer[2352+3] = ((buffer[2352+3]/10)<<4) | (buffer[2352+3]%10);
				buffer[2352+4] = ((buffer[2352+4]/10)<<4) | (buffer[2352+4]%10);
				buffer[2352+5] = ((buffer[2352+5]/10)<<4) | (buffer[2352+5]%10);
				buffer[2352+7] = ((buffer[2352+7]/10)<<4) | (buffer[2352+7]%10);
				buffer[2352+8] = ((buffer[2352+8]/10)<<4) | (buffer[2352+8]%10);
				buffer[2352+9] = ((buffer[2352+9]/10)<<4) | (buffer[2352+9]%10);
			}
			if(crc && crc == calc_crc(10, buffer+2352)) {
				errorCount = 0;
				
				if(adr == 0x1) { // this sector has a pregap info
					if(firstQchannelRead) {
						if(buffer[2354] == 0) { // we are already in the pregap area at the 1st read!
							beginOffset += 75; // begin with 1 more seconds before the current position
							if(disc->tracks[track-2].length/588 <= beginOffset) {
								beginOffset = disc->tracks[track-2].length/588 - 1;
								firstQchannelRead = 0;
							}
							cdread.offset = (disc->tracks[track-1].start/588-beginOffset)*(2352+16);
							continue;
						}
						else firstQchannelRead = 0;
					}
					if(state == 0) {
						if(buffer[2354] == 0) state = 1;
					}
					else if(state == 1) {
						if(buffer[2354] == 0) state = 2;
						else state = 0;
					}
				}
				success = 1;
			}
			else {
				if(!success) {
					totalErrorCount++;
					if(totalErrorCount == 100) {
						if(disc->nonBCD) goto last;
						else {
							disc->nonBCD = 1;
							state = 0;
							errorCount = 0;
							totalErrorCount = 0;
							pregapLength = 0;
							success = 0;
							firstQchannelRead = 1;
							beginOffset = 300; /* 4 sec */
							if(disc->tracks[track-2].length/588 <= 300) {
								beginOffset = disc->tracks[track-2].length/588 - 1;
								firstQchannelRead = 0;
							}
							cdread.offset = (disc->tracks[track-1].start/588-beginOffset)*(2352+16);
							continue;
						}
					}
				}
				errorCount++;
				if(errorCount < 5) continue;
				else errorCount = 0;
			}
		}
		cdread.offset+=2352+16;
		if(cdread.offset > disc->tracks[track-1].start/588*(2352+16)) {
			/* reached next track */
			break;
		}
		if(state > 0) pregapLength++;
		else pregapLength = 0;
	}
	
	disc->tracks[track-1].pregap = pregapLength;
last:
	free(buffer);
}

void xld_cdda_read_mcn(xld_cdread_t *disc)
{
	dk_cd_read_mcn_t mcnread;
	memset(&mcnread,0,sizeof(dk_cd_read_mcn_t));
	int result = ioctl(disc->fd, DKIOCCDREADMCN, &mcnread);
	if(result != -1) {
		//fprintf(stderr,"mcn: %s\n",mcnread.mcn);
		if(strncmp(mcnread.mcn,"0000000000000",13)) {
			strcpy(disc->mcn,mcnread.mcn);
		}
	}
	//else perror("mcn not found");
}

void xld_cdda_read_isrc(xld_cdread_t *disc, int track)
{
	if(track<=0 || track>disc->numTracks || disc->tracks[track-1].type != kTrackTypeAudio) return;
#if 0
	dk_cd_read_isrc_t isrcread;
	memset(&isrcread,0,sizeof(dk_cd_read_isrc_t));
	isrcread.track = track;
	int result = ioctl(disc->fd, DKIOCCDREADISRC, &isrcread);
	if(result != -1) {
		//fprintf(stderr,"isrc: %s\n",isrcread.isrc);
		if(strncmp(isrcread.isrc,"000000000000",12)) {
			strcpy(disc->tracks[track-1].isrc,isrcread.isrc);
		}
	}
	//else perror("isrc not found");
#else
	int errorCount = 0;
	int totalErrorCount = 0;
	int success = 0;
	unsigned char *buffer = malloc(2352+16);
	dk_cd_read_t cdread;
	memset(&cdread, 0, sizeof(cdread));
	cdread.sectorArea = kCDSectorAreaUser | kCDSectorAreaSubChannelQ;
	cdread.sectorType = kCDSectorTypeCDDA;
	cdread.bufferLength = 2352+16;
	cdread.buffer = buffer;
	cdread.offset = (disc->tracks[track-1].start/588)*(2352+16);
	while(1) {
		int result = ioctl(disc->fd, DKIOCCDREAD, &cdread);
		if(result != -1) {
			unsigned int adr = buffer[2352] & 0xf;
			unsigned int crc = buffer[2362]<<8 | buffer[2363];
			if(adr != 0x3 && adr != 0x2) goto nextSector;
			if(crc && crc == calc_crc(10, buffer+2352)) {
				errorCount = 0;
				if(adr == 0x3 && !disc->tracks[track-1].isrc[0]) {
					disc->tracks[track-1].isrc[0]  = isrc2Ascii((buffer[2353] >> 2) & 0x3f);
					disc->tracks[track-1].isrc[1]  = isrc2Ascii(((buffer[2353] & 0x03) << 4) | ((buffer[2354] >> 4) & 0x0f));
					disc->tracks[track-1].isrc[2]  = isrc2Ascii(((buffer[2354] & 0x0f) << 2) | ((buffer[2355] >> 6) & 0x03));
					disc->tracks[track-1].isrc[3]  = isrc2Ascii(buffer[2355] & 0x3f);
					disc->tracks[track-1].isrc[4]  = isrc2Ascii((buffer[2356] >> 2) & 0x3f);
					disc->tracks[track-1].isrc[5]  = ((buffer[2357] >> 4) & 0x0f) + '0';
					disc->tracks[track-1].isrc[6]  = (buffer[2357] & 0x0f) + '0';
					disc->tracks[track-1].isrc[7]  = ((buffer[2358] >> 4) & 0x0f) + '0';
					disc->tracks[track-1].isrc[8]  = (buffer[2358] & 0x0f) + '0';
					disc->tracks[track-1].isrc[9]  = ((buffer[2359] >> 4) & 0x0f) + '0';
					disc->tracks[track-1].isrc[10] = (buffer[2359] & 0x0f) + '0';
					disc->tracks[track-1].isrc[11] = ((buffer[2360] >> 4) & 0x0f) + '0';
					disc->tracks[track-1].isrc[12] = 0;
					//fprintf(stderr,"track %d: found ISRC at offset %lld (%s)\n",track,cdread.offset/(2352+16),disc->tracks[track-1].isrc);
					if(!strcmp(disc->tracks[track-1].isrc,"000000000000")) disc->tracks[track-1].isrc[0] = 0;
				}
				else if(adr == 0x2 && !disc->mcn[0]) {
					disc->mcn[0]  = ((buffer[2353] >> 4) & 0x0f) + '0';
					disc->mcn[1]  = (buffer[2353] & 0x0f) + '0';
					disc->mcn[2]  = ((buffer[2354] >> 4) & 0x0f) + '0';
					disc->mcn[3]  = (buffer[2354] & 0x0f) + '0';
					disc->mcn[4]  = ((buffer[2355] >> 4) & 0x0f) + '0';
					disc->mcn[5]  = (buffer[2355] & 0x0f) + '0';
					disc->mcn[6]  = ((buffer[2356] >> 4) & 0x0f) + '0';
					disc->mcn[7]  = (buffer[2356] & 0x0f) + '0';
					disc->mcn[8]  = ((buffer[2357] >> 4) & 0x0f) + '0';
					disc->mcn[9]  = (buffer[2357] & 0x0f) + '0';
					disc->mcn[10] = ((buffer[2358] >> 4) & 0x0f) + '0';
					disc->mcn[11] = (buffer[2358] & 0x0f) + '0';
					disc->mcn[12] = ((buffer[2359] >> 4) & 0x0f) + '0';
					disc->mcn[13] = 0;
					//fprintf(stderr,"mcn is: %s\n",disc->mcn);
					if(!strcmp(disc->mcn,"0000000000000")) disc->mcn[0] = 0;
				}
				success = 1;
			}
			else {
				if(!success) {
					totalErrorCount++;
					if(totalErrorCount == 100) {
						goto last;
					}
				}
				errorCount++;
				if(errorCount < 5) continue;
				else errorCount = 0;
			}
		}
		
	nextSector:
		cdread.offset+=2352+16;
		if(cdread.offset > (disc->tracks[track-1].start/588 + 150)*(2352+16)) {
			/* read 150 sectors */
			break;
		}
	}
last:
	free(buffer);
#endif
}

int xld_cdda_sector_getsession(xld_cdread_t *disc, int sector)
{
	int track = xld_cdda_sector_gettrack(disc,sector);
	if(track == 0) return 1;
	if(track < 0) {
		int i;
		for(i=1;i<disc->numTracks;i++) {
			if(disc->tracks[i].start > sector) return disc->tracks[i-1].session;
		}
		return disc->tracks[i-1].session;
	}
	return disc->tracks[track-1].session;
}

int xld_cdda_measure_cache(xld_cdread_t *disc)
{
	int i,start,ms,cache=-1;
	char *buf = malloc(2352*1024);
	for(i=0;i<disc->numTracks;i++) {
		if(disc->tracks[i].type == kTrackTypeAudio) break;
	}
	start = disc->tracks[i].start;
	
	//xld_cdda_read(disc, buf, xld_cdda_disc_lastsector_currentsession(disc, 1)-1024, 1024);
	for(i=1;i<1024;i++) {
		int ret = xld_cdda_read(disc, buf, start, i);
		if(ret < 0) break;
		ret = xld_cdda_read_timed(disc, buf, start, 1, &ms);
		if(ret < 0) break;
		if(ms > 5) {
			cache = i-1;
			break;
		}
	}
	
	free(buf);
	return cache;
}

int xld_cdda_set_max_speed(xld_cdread_t *disc, int speed)
{
	disc->maxSpeed = speed;
	return xld_cdda_speed_set(disc,speed);
}
