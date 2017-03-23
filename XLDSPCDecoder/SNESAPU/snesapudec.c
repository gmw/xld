#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "SNESAPU.h"

#define SPC_CMD_TOTALSAMPLES	0x0
#define SPC_CMD_READ_SAMPLES	0x1
#define SPC_CMD_SEEK			0x2
#define SPC_CMD_CLOSE			0x3

int main(int argc, char *argv[])
{
	if(argc<2) return 0;
	
	struct stat stat;
	memset(&stat,0,sizeof(stat));
    
	InitAPU(1);
	SetAPUOpt(3,2,32,32000,7,0);
	
	int bufSize = 8192*4*4;
	unsigned char *buf = malloc(bufSize);
	
	FILE *fp = fopen(argv[1],"rb");
	
	fstat(fileno(fp),&stat);
	unsigned char *spcbuf = calloc(stat.st_size,1);
	
	long long totalSamples = 0;
	int fadeout = 0;
	
	fread(spcbuf,1,stat.st_size,fp);
	fclose(fp);
	
	if(spcbuf[0x23] == 0x1a) {
		if(spcbuf[0xd2] < 0x30) {
			totalSamples = (spcbuf[0xa9] | (spcbuf[0xaa] << 8)) * 32000;
			fadeout = (spcbuf[0xac] | (spcbuf[0xad] << 8) | (spcbuf[0xae] << 16)) * 32;
		}
		else {
			memcpy(buf,spcbuf+0xa9,3);
			buf[3] = 0;
			totalSamples = atoi((char *)buf)*32000;
			memcpy(buf,spcbuf+0xac,5);
			buf[5] = 0;
			fadeout = 32*atoi((char *)buf);
		}
		totalSamples += fadeout;
	}
	
	if(totalSamples == 0) {
		totalSamples = 32000*180;
		fadeout = 32000*10;
	}
	
	LoadSPCFile(spcbuf);
	SetAPULength((totalSamples-fadeout)*2,fadeout*2);
	
	long long currentPos = 0;
	while(1) {
		unsigned char cmd;
		int request,read,i,ret;
		long long int64val;
		if(fread(&cmd,1,1,stdin) != 1) goto last;
		switch(cmd) {
		  case SPC_CMD_TOTALSAMPLES:
			int64val = totalSamples;
			fwrite(&int64val,8,1,stdout);
			fflush(stdout);
			break;
		  case SPC_CMD_READ_SAMPLES:
			fread(&request,4,1,stdin);
			
			if(currentPos+request > totalSamples) {
				request = totalSamples - currentPos;
			}
			
			if(request*4*2 > bufSize) {
				free(buf);
				bufSize = request*4*2;
				buf = (unsigned char *)malloc(bufSize);
			}
			
			if(request) {
				EmuAPU(buf,request,1);
			}
			currentPos += request;
			fwrite(&request,4,1,stdout);
			if(request) fwrite(buf,1,request*4*2,stdout);
			fflush(stdout);
			break;
		  case SPC_CMD_SEEK:
			fread(&int64val,8,1,stdin);
			if(currentPos > int64val) {
				LoadSPCFile(spcbuf);
				if(int64val) SeekAPU(int64val*2,0);
			}
			else if(currentPos < int64val) {
				SeekAPU((int64val - currentPos)*2,0);
			}
			currentPos = int64val;
			ret = 0;
			fwrite(&ret,4,1,stdout);
			fflush(stdout);
			break;
		  case SPC_CMD_CLOSE:
			goto last;
		}
	}
  last:
	
	return 0;
}
