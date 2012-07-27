#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include "tak_deco_lib.h"

#define TAK_CMD_BPS				0x0
#define TAK_CMD_CHANNELS		0x1
#define TAK_CMD_SAMPLERATE		0x2
#define TAK_CMD_TOTALSAMPLES	0x3
#define TAK_CMD_READ_METADATA	0x4
#define TAK_CMD_READ_SAMPLES	0x5
#define TAK_CMD_SEEK			0x6
#define TAK_CMD_CLOSE			0x7
#define TAK_CMD_ISVALID			0x8

int main(int argc, char *argv[])
{
	if(argc<2) return 0;
	
	HANDLE h;
	h = LoadLibrary("tak_deco_lib.dll");
	TtakSeekableStreamDecoder (*tak_SSD_Create_FromFile) (const char *,const TtakSSDOptions *,TSSDDamageCallback,void *);
	TtakInt32 (*tak_SSD_GetFrameSize) (TtakSeekableStreamDecoder);
	TtakResult (*tak_SSD_ReadAudio) (TtakSeekableStreamDecoder,void *,TtakInt32,TtakInt32 *);
	TtakResult (*tak_SSD_GetStreamInfo) (TtakSeekableStreamDecoder,Ttak_str_StreamInfo *);
	TtakResult (*tak_SSD_Seek) (TtakSeekableStreamDecoder,TtakInt64);
	void (*tak_SSD_Destroy) (TtakSeekableStreamDecoder);
	TtakAPEv2Tag (*tak_SSD_GetAPEv2Tag) (TtakSeekableStreamDecoder);
	TtakBool (*tak_SSD_Valid) (TtakSeekableStreamDecoder);
	TtakBool (*tak_APE_Valid) (TtakAPEv2Tag);
	TtakInt32 (*tak_APE_GetItemNum) (TtakAPEv2Tag);
	TtakResult (*tak_APE_GetIndexOfKey) (TtakAPEv2Tag,const char *,TtakInt32 *);
	TtakResult (*tak_APE_GetItemValue) (TtakAPEv2Tag,TtakInt32,void *,TtakInt32,TtakInt32 *);

	tak_SSD_Create_FromFile = GetProcAddress(h,"tak_SSD_Create_FromFile");
	tak_SSD_GetFrameSize = GetProcAddress(h,"tak_SSD_GetFrameSize");
	tak_SSD_ReadAudio = GetProcAddress(h,"tak_SSD_ReadAudio");
	tak_SSD_GetStreamInfo = GetProcAddress(h,"tak_SSD_GetStreamInfo");
	tak_SSD_Seek = GetProcAddress(h,"tak_SSD_Seek");
	tak_SSD_Destroy = GetProcAddress(h,"tak_SSD_Destroy");
	tak_SSD_GetAPEv2Tag = GetProcAddress(h,"tak_SSD_GetAPEv2Tag");
	tak_SSD_Valid = GetProcAddress(h,"tak_SSD_Valid");
	tak_APE_Valid = GetProcAddress(h,"tak_APE_Valid");
	tak_APE_GetItemNum = GetProcAddress(h,"tak_APE_GetItemNum");
	tak_APE_GetIndexOfKey = GetProcAddress(h,"tak_APE_GetIndexOfKey");
	tak_APE_GetItemValue = GetProcAddress(h,"tak_APE_GetItemValue");
	
	TtakBool valid = 0;
	int numTag = 0;
	TtakSSDOptions option = {tak_Cpu_Any,0};
	TtakSeekableStreamDecoder decoder = tak_SSD_Create_FromFile(argv[1],&option,NULL,NULL);
	if(decoder) {
		valid = tak_SSD_Valid(decoder);
	}
	Ttak_str_StreamInfo info;
	TtakAPEv2Tag tag;
	if(valid) {
		tak_SSD_GetStreamInfo(decoder,&info);
		tag = tak_SSD_GetAPEv2Tag(decoder);
		if(tak_APE_Valid(tag)) {
			numTag = tak_APE_GetItemNum(tag);
			numTag = (numTag < 0) ? 0 : numTag;
		}
	}
	
	int bufSize = 8192*4*2;
	unsigned char *buf = (unsigned char *)malloc(bufSize);
	while(1) {
		unsigned char cmd;
		int intVal;
		int request,read,i,ret;
		long long int64val;
		short *ptr;
		char tagKey[32];
		if(fread(&cmd,1,1,stdin) != 1) goto last;
		switch(cmd) {
		  case TAK_CMD_BPS:
			intVal = info.Audio.SampleBits;
			fwrite(&intVal,4,1,stdout);
			break;
		  case TAK_CMD_CHANNELS:
			intVal = info.Audio.ChannelNum;
			fwrite(&intVal,4,1,stdout);
			break;
		  case TAK_CMD_SAMPLERATE:
			intVal = info.Audio.SampleRate;
			fwrite(&intVal,4,1,stdout);
			break;
		  case TAK_CMD_TOTALSAMPLES:
			int64val = info.Sizes.SampleNum;
			fwrite(&int64val,8,1,stdout);
			break;
		  case TAK_CMD_READ_SAMPLES:
			fread(&request,4,1,stdin);
			if(request*info.Audio.SampleBits*info.Audio.ChannelNum/8 > bufSize) {
				free(buf);
				buf = (unsigned char *)malloc(request*info.Audio.SampleBits*info.Audio.ChannelNum/8);
			}
			ret = tak_SSD_ReadAudio(decoder,buf,request,&read);
			if(ret) {
				ret = -1;
				fwrite(&ret,4,1,stdout);
			}
			else if(!read) fwrite(&read,4,1,stdout);
			else {
				fwrite(&read,4,1,stdout);
				fwrite(buf,1,read*info.Audio.SampleBits*info.Audio.ChannelNum/8,stdout);
			}
			break;
		  case TAK_CMD_SEEK:
			fread(&int64val,8,1,stdin);
			ret = tak_SSD_Seek(decoder,int64val);
			fwrite(&ret,4,1,stdout);
			break;
		  case TAK_CMD_ISVALID:
			fwrite(&valid,4,1,stdout);
			break;
		  case TAK_CMD_READ_METADATA:
			fread(&intVal,4,1,stdin);
			fread(tagKey,1,intVal,stdin);
			tagKey[intVal] = 0;
			if(numTag) {
				ret = tak_APE_GetIndexOfKey(tag,tagKey,&i);
				if(!ret) {
					tak_APE_GetItemValue(tag,i,NULL,0,&intVal);
					char *tagBuf = (char *)malloc(intVal+1);
					tak_APE_GetItemValue(tag,i,tagBuf,intVal,&intVal);
					fwrite(&intVal,4,1,stdout);
					fwrite(tagBuf,1,intVal,stdout);
					free(tagBuf);
				}
				else {
					intVal = 0;
					fwrite(&intVal,4,1,stdout);
				}
			}
			else fwrite(&numTag,4,1,stdout);
			break;
		  case TAK_CMD_CLOSE:
			goto last;
		}
	}
  last:
	if(decoder) tak_SSD_Destroy(decoder);
	return 0;
}
