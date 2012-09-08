
# define FloatToUnsigned(f)	((unsigned long)(((long)((f) - 2147483648.0)) + 2147483647L + 1))

#import <Foundation/Foundation.h>
#import <sndfile.h>
#import <unistd.h>
#import <sys/stat.h>
#import <getopt.h>
#import "XLDDecoder.h"
#import "XLDOutput.h"
#import "XLDOutputTask.h"
#import "XLDTrack.h"
#import "XLDRawDecoder.h"
#import "XLDCueParser.h"
#import "XLDDDPParser.h"
#import "XLDecoderCenter.h"
#import "XLDPluginManager.h"
#import "XLDDefaultOutputTask.h"
#import <dlfcn.h>

/*
static OSStatus (*_LSSetApplicationInformationItem)(int, CFTypeRef asn, CFStringRef key, CFStringRef value, CFDictionaryRef *info) = NULL;
static CFTypeRef (*_LSGetCurrentApplicationASN)(void) = NULL;
static CFStringRef _kLSApplicationTypeKey = NULL;
static CFStringRef _kLSApplicationUIElementTypeKey = NULL;

static CFStringRef launchServicesKey(const char *symbol)
{
	CFStringRef *keyPtr = dlsym(RTLD_DEFAULT, symbol);
	return keyPtr ? *keyPtr : NULL;
}
*/

static void ConvertToIeeeExtended(double num, char* bytes)
{
	int    sign;
	int expon;
	double fMant, fsMant;
	unsigned long hiMant, loMant;
	
	if (num < 0) {
		sign = 0x8000;
		num *= -1;
	} else {
		sign = 0;
	}
	
	if (num == 0) {
		expon = 0; hiMant = 0; loMant = 0;
	}
	else {
		fMant = frexp(num, &expon);
		if ((expon > 16384) || !(fMant < 1)) {    /* Infinity or NaN */
			expon = sign|0x7FFF; hiMant = 0; loMant = 0; /* infinity */
		}
		else {    /* Finite */
			expon += 16382;
			if (expon < 0) {    /* denormalized */
				fMant = ldexp(fMant, expon);
				expon = 0;
			}
			expon |= sign;
			fMant = ldexp(fMant, 32);          
			fsMant = floor(fMant); 
			hiMant = FloatToUnsigned(fsMant);
			fMant = ldexp(fMant - fsMant, 32); 
			fsMant = floor(fMant); 
			loMant = FloatToUnsigned(fsMant);
		}
	}
	
	bytes[0] = expon >> 8;
	bytes[1] = expon;
	bytes[2] = hiMant >> 24;
	bytes[3] = hiMant >> 16;
	bytes[4] = hiMant >> 8;
	bytes[5] = hiMant;
	bytes[6] = loMant >> 24;
	bytes[7] = loMant >> 16;
	bytes[8] = loMant >> 8;
	bytes[9] = loMant;
}

static void writeWavHeader(int bps, int channels, int samplerate, int isFloat, unsigned int frames, FILE *fp)
{
	unsigned int tmp1;
	unsigned short tmp2;
	fwrite("RIFF", 1, 4, fp);
	tmp1 = NSSwapHostIntToLittle(frames*bps*channels+36);
	fwrite(&tmp1, 4, 1, fp);
	fwrite("WAVE", 1, 4, fp);
	fwrite("fmt ", 1, 4, fp);
	tmp1 = NSSwapHostIntToLittle(16);
	fwrite(&tmp1, 4, 1, fp);
	tmp2 = isFloat ? 3 : 1;
	tmp2 = NSSwapHostShortToLittle(tmp2);
	fwrite(&tmp2, 2, 1, fp);
	tmp2 = NSSwapHostShortToLittle(channels);
	fwrite(&tmp2, 2, 1, fp);
	tmp1 = NSSwapHostIntToLittle(samplerate);
	fwrite(&tmp1, 4, 1, fp);
	tmp1 = NSSwapHostIntToLittle(bps*channels*samplerate);
	fwrite(&tmp1, 4, 1, fp);
	tmp2 = NSSwapHostShortToLittle(bps*channels);
	fwrite(&tmp2, 2, 1, fp);
	tmp2 = NSSwapHostShortToLittle(bps*8);
	fwrite(&tmp2, 2, 1, fp);
	fwrite("data", 1, 4, fp);
	tmp1 = NSSwapHostIntToLittle(frames*bps*channels);
	fwrite(&tmp1, 4, 1, fp);
}

static void writeAiffHeader(int bps, int channels, int samplerate, int isFloat, unsigned int frames, FILE *fp)
{
	unsigned int tmp1;
	unsigned short tmp2;
	char ieeeExtended[10];
	if(isFloat) {
		fwrite("FORM", 1, 4, fp);
		tmp1 = NSSwapHostIntToBig(frames*bps*channels+64);
		fwrite(&tmp1, 4, 1, fp);
		fwrite("AIFC", 1, 4, fp);
		fwrite("FVER", 1, 4, fp);
		tmp1 = NSSwapHostIntToBig(4);
		fwrite(&tmp1, 4, 1, fp);
		tmp1 = NSSwapHostIntToBig(0xa2805140);
		fwrite(&tmp1, 4, 1, fp);
		fwrite("COMM", 1, 4, fp);
		tmp1 = NSSwapHostIntToBig(24);
		fwrite(&tmp1, 4, 1, fp);
		tmp2 = NSSwapHostShortToBig(channels);
		fwrite(&tmp2, 2, 1, fp);
		tmp1 = NSSwapHostIntToBig(frames);
		fwrite(&tmp1, 4, 1, fp);
		tmp2 = NSSwapHostShortToBig(bps*8);
		fwrite(&tmp2, 2, 1, fp);
		ConvertToIeeeExtended(samplerate,ieeeExtended);
		fwrite(ieeeExtended, 1, 10, fp);
		fwrite("FL32", 1, 4, fp);
		tmp2 = 0;
		fwrite(&tmp2, 2, 1, fp);
		fwrite("SSND", 1, 4, fp);
		tmp1 = NSSwapHostIntToBig(frames*bps*channels+8);
		fwrite(&tmp1, 4, 1, fp);
		tmp1 = 0;
		fwrite(&tmp1, 4, 1, fp);
		fwrite(&tmp1, 4, 1, fp);
		
	}
	else {
		fwrite("FORM", 1, 4, fp);
		tmp1 = NSSwapHostIntToBig(frames*bps*channels+46);
		fwrite(&tmp1, 4, 1, fp);
		fwrite("AIFF", 1, 4, fp);
		fwrite("COMM", 1, 4, fp);
		tmp1 = NSSwapHostIntToBig(18);
		fwrite(&tmp1, 4, 1, fp);
		tmp2 = NSSwapHostShortToBig(channels);
		fwrite(&tmp2, 2, 1, fp);
		tmp1 = NSSwapHostIntToBig(frames);
		fwrite(&tmp1, 4, 1, fp);
		tmp2 = NSSwapHostShortToBig(bps*8);
		fwrite(&tmp2, 2, 1, fp);
		ConvertToIeeeExtended(samplerate,ieeeExtended);
		fwrite(ieeeExtended, 1, 10, fp);
		fwrite("SSND", 1, 4, fp);
		tmp1 = NSSwapHostIntToBig(frames*bps*channels+8);
		fwrite(&tmp1, 4, 1, fp);
		tmp1 = 0;
		fwrite(&tmp1, 4, 1, fp);
		fwrite(&tmp1, 4, 1, fp);
	}
}

static void writeSamples(int *samples, unsigned int numSamples, int bps, int endian, FILE *fp)
{
	unsigned int i;
	for(i=0;i<numSamples;i++) {
		if(bps==1) {
			char sample = samples[i] >> 24;
			if(endian) sample += 0x80;
			fwrite(&sample, 1, 1, fp);
		}
		else if(bps==2) {
			short sample = samples[i] >> 16;
			if(endian) sample = NSSwapHostShortToLittle(sample);
			else sample = NSSwapHostShortToBig(sample);
			fwrite(&sample, 2, 1, fp);
		}
		else if(bps==3) {
			unsigned char sample[3];
			if(endian) {
				sample[0] = (samples[i] >> 8) & 0xff;
				sample[1] = (samples[i] >> 16) & 0xff;
				sample[2] = (samples[i] >> 24) & 0xff;
			}
			else {
				sample[0] = (samples[i] >> 24) & 0xff;
				sample[1] = (samples[i] >> 16) & 0xff;
				sample[2] = (samples[i] >> 8) & 0xff;
			}
			fwrite(sample, 1, 3, fp);
		}
		else {
			int sample = samples[i];
			if(endian) sample = NSSwapHostIntToLittle(sample);
			else sample = NSSwapHostIntToBig(sample);
			fwrite(&sample, 4, 1, fp);
		}
	}
	fflush(fp);
}

static void usage(void)
{
	fprintf(stderr,"X Lossless Decoder %s by tmkk\n",[[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"] UTF8String]);
	fprintf(stderr,"usage: xld [-c cuesheet] [--ddpms DDPMSfile] [-e] [-f format] [-o outpath] [-t track] [--raw] file\n");
	fprintf(stderr,"\t-c: Cue sheet you want to split file with\n");
	fprintf(stderr,"\t-e: Exclude pre-gap from decoded file\n");
	fprintf(stderr,"\t-f: Specify format of decoded file\n");
	fprintf(stderr,"\t      wav        : Microsoft WAV (default)\n");
	fprintf(stderr,"\t      aif        : Apple AIFF\n");
	fprintf(stderr,"\t      raw_big    : Raw PCM (big endian)\n");
	fprintf(stderr,"\t      raw_little : Raw PCM (little endian)\n");
	fprintf(stderr,"\t      mp3        : LAME MP3\n");
	fprintf(stderr,"\t      aac        : MPEG-4 AAC\n");
	fprintf(stderr,"\t      flac       : FLAC\n");
	fprintf(stderr,"\t      alac       : Apple Lossless\n");
	fprintf(stderr,"\t      vorbis     : Ogg Vorbis\n");
	fprintf(stderr,"\t      wavpack    : WavPack\n");
	fprintf(stderr,"\t-o: Specify path of decoded file\n\t    (directory or filename; directory only for cue sheet mode)\n");
	fprintf(stderr,"\t-t: List of tracks you want to decode; ex. -t 1,3,4\n");
	fprintf(stderr,"\t--raw: Force read input file as Raw PCM\n\t       following 4 options are required\n");
	fprintf(stderr,"\t  --samplerate: Samplerate of Raw PCM file; default=44100\n");
	fprintf(stderr,"\t  --bit       : Bit depth of Raw PCM file; default=16\n");
	fprintf(stderr,"\t  --channels  : Number of channels of Raw PCM file; default=2\n");
	fprintf(stderr,"\t  --endian    : Endian of Raw PCM file (little or big); default=little\n");
	fprintf(stderr,"\t--correct-30samples: Correct \"30 samples moved offset\" problem\n");
	fprintf(stderr,"\t--ddpms: DDPMS file (assumes that the associated file is Raw PCM)\n");
	fprintf(stderr,"\t--stdout: write output to stdout (-o option is ignored)\n");
}

int cmdline_main(int argc, char *argv[])
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	unsigned int sf_format = SF_FORMAT_WAV;
	int i,useCueSheet=0,ignoreGap=0,debug=0,useDdpms=0,writeToStdout=0;;
	int offset = 0;
	char *cuesheet = NULL;
	char *trks = NULL;
	char *outdir = NULL;
	char *ddpms = NULL;
	const char *outfile = NULL;
	NSString *extStr = nil;
	XLDFormat outputFormat;
	int rawMode = 0;
	outputFormat.samplerate = 44100;
	outputFormat.channels = 2;
	int rawEndian = XLDLittleEndian;
	outputFormat.bps = 2;
	outputFormat.isFloat = 0;
	Class customOutputClass = nil;
	id encoder = nil;
	BOOL acceptStdoutWriting = YES;
	
	int		ch;
	extern char	*optarg;
	extern int	optind, opterr;
	int option_index;
	struct option options[] = {
		{"raw", 0, NULL, 0},
		{"samplerate", 1, NULL,0},
		{"endian", 1, NULL, 0},
		{"bit", 1, NULL, 0},
		{"channels", 1, NULL, 0},
		{"read-embedded-cuesheet", 0, NULL, 0},
		{"ignore-embedded-cuesheet", 0, NULL, 0},
		{"correct-30samples", 0, NULL, 0},
		{"ddpms", 1, NULL, 0},
		{"stdout", 0, NULL, 0},
		{"cmdline", 0, NULL, 0},
		{0, 0, 0, 0}
	};
	
	XLDPluginManager *pluginManager = [[XLDPluginManager alloc] init];
	XLDecoderCenter *decoderCenter = [[XLDecoderCenter alloc] initWithPlugins:[pluginManager plugins]];
	XLDCueParser *cueParser = [[XLDCueParser alloc] initWithDelegate:nil];
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	if([pref objectForKey:@"CuesheetEncodings2"]) {
		[cueParser setPreferredEncoding:[[pref objectForKey:@"CuesheetEncodings2"] unsignedIntValue]];
	}
	
	while ((ch = getopt_long(argc, argv, "c:et:do:f:", options, &option_index)) != -1){
		switch (ch){
			case 0:
				if(!strncmp(options[option_index].name, "raw", 3)) {
					rawMode = 1;
				}
				else if(!strncmp(options[option_index].name, "samplerate", 10)) {
					outputFormat.samplerate = atoi(optarg);
				}
				else if(!strncmp(options[option_index].name, "endian", 6)) {
					if(!strncasecmp(optarg,"little",6)) rawEndian = XLDLittleEndian;
					else if(!strncasecmp(optarg,"big",3)) rawEndian = XLDBigEndian;
				}
				else if(!strncmp(options[option_index].name, "bit", 3)) {
					outputFormat.bps = atoi(optarg) >> 3;
				}
				else if(!strncmp(options[option_index].name, "channels", 8)) {
					outputFormat.channels = atoi(optarg);
				}
				else if(!strncmp(options[option_index].name, "correct-30samples", 17)) {
					offset = 30;
				}
				else if(!strncmp(options[option_index].name, "ddpms", 5)) {
					ddpms = optarg;
					useDdpms = 1;
					rawMode = 1;
				}
				else if(!strncmp(options[option_index].name, "stdout", 6)) {
					writeToStdout = 1;
				}
				else if(!strncmp(options[option_index].name, "cmdline", 7)) {
					//skip
				}
				break;
			case 'c':
				cuesheet = optarg;
				useCueSheet = 1;
				break;
			case 'e':
				ignoreGap = 1;
				break;
			case 't':
				trks = optarg;
				break;
			case 'd':
				debug = 1;
				break;
			case 'o':
				outfile = optarg;
				break;
			case 'f':
				if(!strcasecmp(optarg,"wav")) {
					sf_format = SF_FORMAT_WAV;
					customOutputClass = (Class)objc_lookUpClass("XLDWavOutput");
					if(!customOutputClass) {
						fprintf(stderr,"error: Wav output plugin not loaded\n");
						return -1;
					}
					acceptStdoutWriting = YES;
				}
				else if(!strcasecmp(optarg,"aif")) {
					sf_format = SF_FORMAT_AIFF;
					customOutputClass = (Class)objc_lookUpClass("XLDAiffOutput");
					if(!customOutputClass) {
						fprintf(stderr,"error: AIFF output plugin not loaded\n");
						return -1;
					}
					acceptStdoutWriting = YES;
				}
				else if(!strcasecmp(optarg,"raw_big")) {
					sf_format = SF_FORMAT_RAW|SF_ENDIAN_BIG;
					customOutputClass = (Class)objc_lookUpClass("XLDPCMBEOutput");
					if(!customOutputClass) {
						fprintf(stderr,"error: PCM (big endian) output plugin not loaded\n");
						return -1;
					}
					acceptStdoutWriting = YES;
				}
				else if(!strcasecmp(optarg,"raw_little")) {
					sf_format = SF_FORMAT_RAW|SF_ENDIAN_LITTLE;
					customOutputClass = (Class)objc_lookUpClass("XLDPCMLEOutput");
					if(!customOutputClass) {
						fprintf(stderr,"error: PCM (little endian) output plugin not loaded\n");
						return -1;
					}
					acceptStdoutWriting = YES;
				}
				else if(!strcasecmp(optarg,"mp3")) {
					customOutputClass = (Class)objc_lookUpClass("XLDLameOutput");
					if(!customOutputClass) {
						fprintf(stderr,"error: MP3 output plugin not loaded\n");
						return -1;
					}
					acceptStdoutWriting = NO;
				}
				else if(!strcasecmp(optarg,"aac")) {
					customOutputClass = (Class)objc_lookUpClass("XLDAacOutput2");
					if(!customOutputClass) {
						customOutputClass = (Class)objc_lookUpClass("XLDAacOutput");
						if(!customOutputClass) {
							fprintf(stderr,"error: AAC output plugin not loaded\n");
							return -1;
						}
					}
					acceptStdoutWriting = NO;
				}
				else if(!strcasecmp(optarg,"flac")) {
					customOutputClass = (Class)objc_lookUpClass("XLDFlacOutput");
					if(!customOutputClass) {
						fprintf(stderr,"error: FLAC output plugin not loaded\n");
						return -1;
					}
					acceptStdoutWriting = NO;
				}
				else if(!strcasecmp(optarg,"alac")) {
					customOutputClass = (Class)objc_lookUpClass("XLDAlacOutput");
					if(!customOutputClass) {
						fprintf(stderr,"error: FLAC output plugin not loaded\n");
						return -1;
					}
					acceptStdoutWriting = NO;
				}
				else if(!strcasecmp(optarg,"vorbis")) {
					customOutputClass = (Class)objc_lookUpClass("XLDVorbisOutput");
					if(!customOutputClass) {
						fprintf(stderr,"error: Ogg Vorbis output plugin not loaded\n");
						return -1;
					}
					acceptStdoutWriting = NO;
				}
				else if(!strcasecmp(optarg,"wavpack")) {
					customOutputClass = (Class)objc_lookUpClass("XLDWavpackOutput");
					if(!customOutputClass) {
						fprintf(stderr,"error: WavPack output plugin not loaded\n");
						return -1;
					}
					acceptStdoutWriting = NO;
				}
				else sf_format = SF_FORMAT_WAV;
				break;
			default:
				usage();
				return 0;
		}
	}
	
	//argc -= optind;
	//argv += optind;
	if(!argv[optind]) {
		usage();
		return -1; 
	}
	
	if(writeToStdout && !acceptStdoutWriting) {
		fprintf(stderr,"error: writing to stdout does not work with this encoder.\n");
		return -1;
	}
	
	if(outfile) {
		struct stat sb;
		i = stat(outfile,&sb);
		if(!i && S_ISDIR(sb.st_mode)) {
			char *tmp = malloc(512);
			outdir = realpath(outfile, tmp);
			outfile = NULL;
		}
		else {
			char *tmp = malloc(512);
			outfile = realpath(outfile, tmp);
		}
	}
	if(!outdir) {
		char *tmp = malloc(512);
		outdir = realpath("./", tmp);
	}
	
	id decoder;
	
	NSMutableArray* trackList;
	XLDDDPParser *ddpParser = [[XLDDDPParser alloc] init];
	if(useDdpms) {
		if([ddpParser openDDPMS:[NSString stringWithUTF8String:ddpms]]) {
			trackList = [[ddpParser trackListArray] retain];
		}
		else {
			fprintf(stderr,"Error while parsing DDPMS\n");
			return -1;
		}
	}
	else trackList = [[NSMutableArray alloc] init];
	
	if(rawMode) {
		if(useDdpms) decoder = [[XLDRawDecoder alloc] initWithFormat:outputFormat endian:rawEndian offset:[ddpParser offsetBytes]];
		else decoder = [[XLDRawDecoder alloc] initWithFormat:outputFormat endian: rawEndian];
	}
	else {
		decoder = [decoderCenter preferredDecoderForFile:[NSString stringWithUTF8String:argv[optind]]];
		if(!decoder) {
			fprintf(stderr,"error: cannot handle file\n");
			return -1;
		}
	}
	
	if(![decoder conformsToProtocol:@protocol(XLDDecoder)]) {
		fprintf(stderr,"invalid decoder class\n");
		return -1;
	}
	
	if(![(id <XLDDecoder>)decoder openFile:argv[optind]]) {
		fprintf(stderr,"error: cannot open file\n");
		[decoder closeFile];
		return -1;
	}
	
	outputFormat.bps = [decoder bytesPerSample];
	outputFormat.channels = [decoder channels];
	outputFormat.samplerate = [decoder samplerate];
	outputFormat.isFloat = [decoder isFloat];
	
	NSMutableDictionary *configDic = [NSMutableDictionary dictionary];
	[configDic setObject:[NSNumber numberWithInt:0] forKey:@"BitDepth"];
	[configDic setObject:[NSNumber numberWithBool:NO] forKey:@"IsFloat"];
	[configDic setObject:[NSNumber numberWithUnsignedInt:sf_format] forKey:@"SFFormat"];
	
	if(!customOutputClass) {
		customOutputClass = (Class)objc_lookUpClass("XLDWavOutput");
		if(!customOutputClass) {
			fprintf(stderr,"error: Wav output plugin not loaded\n");
			return -1;
		}
	}
#if 1
	{
		/*_LSSetApplicationInformationItem = dlsym(RTLD_DEFAULT, "_LSSetApplicationInformationItem");
		_LSGetCurrentApplicationASN = dlsym(RTLD_DEFAULT, "_LSGetCurrentApplicationASN");
		_kLSApplicationTypeKey = launchServicesKey("_kLSApplicationTypeKey");
		_kLSApplicationUIElementTypeKey = launchServicesKey("_kLSApplicationUIElementTypeKey");
		
		if(!_LSSetApplicationInformationItem) NSLog(@"_LSSetApplicationInformationItem is null");
		if(!_LSGetCurrentApplicationASN) NSLog(@"_LSGetCurrentApplicationASN is null");
		if(!_kLSApplicationTypeKey) NSLog(@"_kLSApplicationTypeKey is null");
		if(!_kLSApplicationUIElementTypeKey) NSLog(@"_kLSApplicationUIElementTypeKey is null");*/
		
		encoder = [[customOutputClass alloc] init];
		[encoder loadPrefs];
		id tmpTask = [encoder createTaskForOutput];
		extStr = [tmpTask extensionStr];
		[tmpTask release];
		NSString *desc = [[(id <XLDOutput>)encoder configurations] objectForKey:@"ShortDesc"];
		if(desc) fprintf(stderr,"Encoder option: %s\n",[desc UTF8String]);
		//[encoder release];
		
		/*if(_LSSetApplicationInformationItem && _LSGetCurrentApplicationASN && _kLSApplicationTypeKey && _kLSApplicationUIElementTypeKey)
			_LSSetApplicationInformationItem(-2, _LSGetCurrentApplicationASN(), _kLSApplicationTypeKey, _kLSApplicationUIElementTypeKey, NULL);*/
	}
#endif
	//SetSystemUIMode(kUIModeAllHidden, 0);
	//[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
	
	if(useCueSheet) {
		[cueParser setTrackData:trackList forCueFile:[NSString stringWithUTF8String:cuesheet] withDecoder:decoder];
		if(![trackList count]) fprintf(stderr,"cannot open cue sheet; ignored.\n");
		if(debug) {
			for(i=0;i<[trackList count];i++) {
				fprintf(stderr,"index:%lld frames:%lld gap:%d\n",[(XLDTrack *)[trackList objectAtIndex:i] index],[[trackList objectAtIndex:i] frames],[[trackList objectAtIndex:i] gap]);
				fprintf(stderr,"title:%s artist:%s\n",[[[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_TITLE] UTF8String],[[[[trackList objectAtIndex:i] metadata] objectForKey:XLD_METADATA_ARTIST] UTF8String]);
			}
		}
	}
	if(![trackList count]) {
		useCueSheet = 0;
		XLDTrack *trk = [[XLDTrack alloc] init];
		[trackList addObject:trk];
		[trk setMetadata:[decoder metadata]];
		[trk release];
	}
	
	if(trks && useCueSheet) {
		char *tmp;
		for(i=0;i<[trackList count];i++) {
			[[trackList objectAtIndex:i] setEnabled:NO];
		}
		tmp = strtok(trks, "," );
		while (tmp != NULL) {
			int t = atoi(tmp)-1;
			if(t >= 0 && t < [trackList count]) [[trackList objectAtIndex:t] setEnabled:YES];
			tmp = strtok(NULL, "," );
		}
	}
	
	unsigned char *buffer = (unsigned char *)malloc(8192*4*outputFormat.channels);
	
	int track;
	int lastPercent = -1;
	for(track=0;track<[trackList count];track++) {
		id <XLDOutputTask> outputTask = nil;
		int samplesperloop = 8192;
		int lasttrack = 0;
		XLDTrack *trk = [trackList objectAtIndex:track];
		if(![trk enabled]) continue;
		
		if(offset) {
			if([trk index] >= offset) [decoder seekToFrame:[trk index]-offset];
			else [decoder seekToFrame:[trk index]];
		}
		else [decoder seekToFrame:[trk index]];
		if([(id <XLDDecoder>)decoder error]) {
			fprintf(stderr,"error: cannot seek\n");
			continue;
		}
		NSString *outputPathStr;
		if(useCueSheet || useDdpms || !outfile) {
			if(!useCueSheet && !useDdpms)
				outputPathStr = [[[[NSString stringWithUTF8String:argv[optind]] lastPathComponent] stringByDeletingPathExtension] stringByAppendingPathExtension:extStr];
			else if([[trk metadata] objectForKey:XLD_METADATA_TITLE] && [[trk metadata] objectForKey:XLD_METADATA_ARTIST])
				outputPathStr = [NSString stringWithFormat:@"%02d %@ - %@.%@",track+1,[[trk metadata] objectForKey:XLD_METADATA_ARTIST],[[trk metadata] objectForKey:XLD_METADATA_TITLE],extStr];
			else if([[trk metadata] objectForKey:XLD_METADATA_TITLE])
				outputPathStr = [NSString stringWithFormat:@"%02d %@.%@",track+1,[[trk metadata] objectForKey:XLD_METADATA_TITLE],extStr];
			else if([[trk metadata] objectForKey:XLD_METADATA_ARTIST])
				outputPathStr = [NSString stringWithFormat:@"%02d %@ - Track %02d.%@",track+1,[[trk metadata] objectForKey:XLD_METADATA_ARTIST],track+1,extStr];
			else
				outputPathStr = [NSString stringWithFormat:@"%02d Track %02d.%@",track+1,track+1,extStr];
			outfile = [[[NSString stringWithUTF8String:outdir] stringByAppendingPathComponent:outputPathStr] UTF8String];
		}
		
		int framesToCopy = [trk frames];
		int totalSize;
		if(framesToCopy != -1) {
			if(!ignoreGap) framesToCopy += [[trackList objectAtIndex:track+1] gap];
		}
		else {
			if(offset) {
				framesToCopy = [decoder totalFrames] - [trk index];
			}
			else {
				lasttrack = 1;
				framesToCopy = [decoder totalFrames] - [trk index];
			}
		}
		totalSize = framesToCopy;
		
		if(!writeToStdout) {
			if(encoder) {
				outputTask = [encoder createTaskForOutput];
			}
			else {
				outputTask = [[XLDDefaultOutputTask alloc] initWithConfigurations:configDic];
			}
			[outputTask setEnableAddTag:YES];
			if(![outputTask setOutputFormat:outputFormat]) {
				fprintf(stderr,"error: incompatible format (unsupported bitdepth or something)\n");
				break;
			}
			if(![outputTask openFileForOutput:[NSString stringWithUTF8String:outfile] withTrackData:trk]) {
				fprintf(stderr,"error: cannot write file %s\n",outfile);
				[(id)outputTask release];
				continue;
			}
		}
		else {
			if((sf_format & SF_FORMAT_WAV) == SF_FORMAT_WAV) {
				writeWavHeader(outputFormat.bps, outputFormat.channels, outputFormat.samplerate, outputFormat.isFloat, framesToCopy, stdout);
			}
			else if((sf_format & SF_FORMAT_AIFF) == SF_FORMAT_AIFF) {
				writeAiffHeader(outputFormat.bps, outputFormat.channels, outputFormat.samplerate, outputFormat.isFloat, framesToCopy, stdout);
			}
		}
		
		if(offset && ([trk index] < offset)) {
			int *tmpbuf = (int *)calloc(offset*outputFormat.channels,4);
			if(!writeToStdout) {
				if(![outputTask writeBuffer:tmpbuf frames:offset - [trk index]]) {
					fprintf(stderr,"error: cannot output sample\n");
					break;
				}
			}
			else {
				writeSamples(tmpbuf,(offset - [trk index])*outputFormat.channels,outputFormat.bps,0,stdout);
			}
			framesToCopy -= (offset - [trk index]);
			free(tmpbuf);
		}
		
		do {
			if(!lasttrack && framesToCopy < samplesperloop) samplesperloop = framesToCopy;
			xldoffset_t ret = [decoder decodeToBuffer:(int *)buffer frames:samplesperloop];
			if([(id <XLDDecoder>)decoder error]) {
				fprintf(stderr,"error: cannot decode\n");
				break;
			}
			//NSLog(@"%d,%d",ret,samplesperloop);
			framesToCopy -= ret;
			if(ret > 0) {
				if(!writeToStdout) {
					if(![outputTask writeBuffer:(int *)buffer frames:ret]) {
						fprintf(stderr,"error: cannot output sample\n");
						break;
					}
				}
				else {
					int endian = 0;
					if((sf_format & SF_FORMAT_WAV) == SF_FORMAT_WAV || (sf_format & (SF_FORMAT_RAW|SF_ENDIAN_LITTLE)) == (SF_FORMAT_RAW|SF_ENDIAN_LITTLE)) endian = 1;
					writeSamples((int *)buffer,ret*outputFormat.channels,outputFormat.bps,endian,stdout);
				}
			}
			int percent = (int)(100.0*(totalSize-framesToCopy)/totalSize);
			if(percent != lastPercent) {
				fprintf(stderr,"\r|");
				for(i=0;i<20;i++) {
					if(percent/5 > i)
						fprintf(stderr,"=");
					else if(percent/5 == i)
						fprintf(stderr,">");
					else fprintf(stderr,"-");
				}
				fprintf(stderr,"| %3d%% (Track %d/%d)",percent,track+1,[trackList count]);
				fflush(stderr);
				lastPercent = percent;
			}
			if((!lasttrack && !framesToCopy) || ret < samplesperloop) {
				break;
			}
		} while(1);
		if(!writeToStdout) {
			[outputTask finalize];
			[outputTask closeFile];
			[(id)outputTask release];
		}
		//if(ignoreGap && [trk gap]) [decoder seekToFrame:[[trackList objectAtIndex:track+1] index]];
	}
	fprintf(stderr,"\ndone.\n");
	[decoder closeFile];
	free(buffer);
	[trackList release];
	[pool release];
	return 0;
}
