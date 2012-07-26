#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "XLDAlacDecoder.h"
#import "XLDTrack.h"

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
#define XLD_METADATA_COVER		@"Cover"
#define XLD_METADATA_ALBUMARTIST	@"AlbumArtist"
#define XLD_METADATA_COMPILATION	@"Compilation"
#define XLD_METADATA_GROUP		@"Group"
#define XLD_METADATA_GRACENOTE		@"Gracenote"
#define XLD_METADATA_BPM		@"BPM"
#define XLD_METADATA_COPYRIGHT	@"Copyright"
#define XLD_METADATA_GAPLESSALBUM	@"GaplessAlbum"
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

static const char* ID3v1GenreList[] = {
    "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk",
    "Grunge", "Hip-Hop", "Jazz", "Metal", "New Age", "Oldies",
    "Other", "Pop", "R&B", "Rap", "Reggae", "Rock",
    "Techno", "Industrial", "Alternative", "Ska", "Death Metal", "Pranks",
    "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk",
    "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House",
    "Game", "Sound Clip", "Gospel", "Noise", "AlternRock", "Bass",
    "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock",
    "Ethnic", "Gothic", "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk",
    "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
    "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret",
    "New Wave", "Psychadelic", "Rave", "Showtunes", "Trailer", "Lo-Fi",
    "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical",
    "Rock & Roll", "Hard Rock", "Folk", "Folk/Rock", "National Folk", "Swing",
    "Fast-Fusion", "Bebob", "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde",
    "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock", "Big Band",
    "Chorus", "Easy Listening", "Acoustic", "Humour", "Speech", "Chanson",
    "Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass", "Primus",
    "Porn Groove", "Satire", "Slow Jam", "Club", "Tango", "Samba",
    "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle", "Duet",
    "Punk Rock", "Drum Solo", "A capella", "Euro-House", "Dance Hall",
    "Goa", "Drum & Bass", "Club House", "Hardcore", "Terror",
    "Indie", "BritPop", "NegerPunk", "Polsk Punk", "Beat",
    "Christian Gangsta", "Heavy Metal", "Black Metal", "Crossover", "Contemporary C",
    "Christian Rock", "Merengue", "Salsa", "Thrash Metal", "Anime", "JPop",
    "SynthPop",
};

static xldoffset_t getTotalFrames(FILE *fp)
{
	char atom[4];
	int tmp,tmp2,tmp3,tmp4,i,j,k,n,m;
	off_t initPos = ftello(fp);
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
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"moov",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	while(1) { //skip until trak;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"trak",4)) {
			/* trak found; check if this track is a sound track */
			off_t trakPos = ftello(fp);
			while(1) { //skip until mdia;
				if(fread(&tmp,4,1,fp) < 1) goto end;
				if(fread(atom,1,4,fp) < 4) goto end;
				tmp = NSSwapBigIntToHost(tmp);
				if(!memcmp(atom,"mdia",4)) break;
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			while(1) { //skip until hdlr;
				if(fread(&tmp,4,1,fp) < 1) goto end;
				if(fread(atom,1,4,fp) < 4) goto end;
				tmp = NSSwapBigIntToHost(tmp);
				if(!memcmp(atom,"hdlr",4)) break;
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			if(fseeko(fp,8,SEEK_CUR) != 0) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			if(!memcmp(atom,"soun",4)) {
				/* sound track found */
				if(fseeko(fp,trakPos,SEEK_SET) != 0) goto end;
				break;
			}
			if(fseeko(fp,trakPos-8,SEEK_SET) != 0) goto end;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			tmp = NSSwapBigIntToHost(tmp);
			if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
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
	
	off_t stblPos = ftello(fp);
	
	while(1) { //skip until stts;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"stts",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
	if(fread(&n,4,1,fp) < 1) goto end;
	n = NSSwapBigIntToHost(n);
	m=0;
	for(i=0;i<n;i++) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(&tmp2,4,1,fp) < 1) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		tmp2 = NSSwapBigIntToHost(tmp2);
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
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"stsz",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	if(fseeko(fp,8,SEEK_CUR) != 0) goto end;
	if(fread(&tmp,4,1,fp) < 1) goto end;
	totalALACFrames = NSSwapBigIntToHost(tmp);
	if(totalALACFrames != m) goto end;
	ALACFrameSizeTable = (int *)calloc(totalALACFrames,sizeof(int));
	ALACFrameToChunkTable = (int *)malloc(totalALACFrames*sizeof(int));
	memset(ALACFrameToChunkTable, -1, totalALACFrames*sizeof(int));
	for(i=0;i<totalALACFrames;i++) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		ALACFrameSizeTable[i] = NSSwapBigIntToHost(tmp);
	}
	
	//fprintf(stderr,"totalALACFrames: %d\n",totalALACFrames);
	
	if(fseeko(fp,stblPos,SEEK_SET) != 0) goto end;
	
	while(1) { //skip until stsc;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"stsc",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
	if(fread(&n,4,1,fp) < 1) goto end;
	n = NSSwapBigIntToHost(n);
	m=0;
	tmp = -1;
	tmp3 = 0;
	tmp4 = 0;
	for(i=0;i<n&&m<totalALACFrames;i++) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(&tmp2,4,1,fp) < 1) goto end;
		if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		tmp2 = NSSwapBigIntToHost(tmp2);
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
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"stco",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
	if(fread(&n,4,1,fp) < 1) goto end;
	n = NSSwapBigIntToHost(n);
	chunkIndexTable = (unsigned int *)calloc(n,sizeof(unsigned int));
	for(i=0;i<n;i++) {
		if(fread(&tmp,4,1,fp) < 1) goto end;
		chunkIndexTable[i] = NSSwapBigIntToHost(tmp);
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
			totalSamples -= lastALACFrameSampleCount;
		}
	}
	
end:
	fseeko(fp,initPos,SEEK_SET);
	if(ALACFrameSizeTable) free(ALACFrameSizeTable);
	if(ALACFrameToChunkTable) free(ALACFrameToChunkTable);
	if(chunkIndexTable) free(chunkIndexTable);
	return totalSamples;
}

NSMutableArray *getChapterTrackList(FILE *fp, int samplerate)
{
	off_t initPos = ftello(fp);
	unsigned int timescale;
	unsigned int duration;
	int i,j,entries,tmp;
	char atom[4];
	NSMutableArray *trackList = [NSMutableArray array];
	NSMutableArray *sampleSizeList = [NSMutableArray array];
	
	/* find text track (ID=2) */
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
			/* trak found; check if this track is a text track */
			off_t trakPos = ftello(fp);
			while(1) { //skip until mdia;
				if(fread(&tmp,4,1,fp) < 1) goto end;
				if(fread(atom,1,4,fp) < 4) goto end;
				tmp = NSSwapBigIntToHost(tmp);
				if(!memcmp(atom,"mdia",4)) break;
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			while(1) { //skip until hdlr;
				if(fread(&tmp,4,1,fp) < 1) goto end;
				if(fread(atom,1,4,fp) < 4) goto end;
				tmp = NSSwapBigIntToHost(tmp);
				if(!memcmp(atom,"hdlr",4)) break;
				if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
			}
			if(fseeko(fp,8,SEEK_CUR) != 0) goto end;
			if(fread(atom,1,4,fp) < 4) goto end;
			if(!memcmp(atom,"text",4)) {
				/* text track found */
				if(fseeko(fp,trakPos,SEEK_SET) != 0) goto end;
				break;
			}
			if(fseeko(fp,trakPos-8,SEEK_SET) != 0) goto end;
			if(fread(&tmp,4,1,fp) < 1) goto end;
			tmp = NSSwapBigIntToHost(tmp);
			if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
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
	
	off_t mdiaPos = ftello(fp);
	
	while(1) { //skip until mdhd;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"mdhd",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	if(fseeko(fp,12,SEEK_CUR) != 0) goto end;
	if(fread(&timescale,4,1,fp) < 1) goto end;
	if(fread(&duration,4,1,fp) < 1) goto end;
	timescale = NSSwapBigIntToHost(timescale);
	duration = NSSwapBigIntToHost(duration);
	
	if(fseeko(fp,mdiaPos,SEEK_SET) != 0) goto end;
	
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
	
	off_t stblPos = ftello(fp);
	
	while(1) { //skip until stts;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"stts",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
	if(fread(&entries,4,1,fp) < 1) goto end;
	entries = NSSwapBigIntToHost(entries);
	xldoffset_t offset = 0;
	for(i=0;i<entries;i++) {
		int sampleCount;
		if(fread(&sampleCount,4,1,fp) < 1) goto end;
		sampleCount = NSSwapBigIntToHost(sampleCount);
		if(fread(&tmp,4,1,fp) < 1) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		xldoffset_t sample = (xldoffset_t)roundf((float)tmp*samplerate/timescale);
		for(j=0;j<sampleCount;j++) {
			XLDTrack *track = [[objc_getClass("XLDTrack") alloc] init];
			[track setIndex:offset];
			[track setFrames:sample];
			offset += sample;
			[trackList addObject:track];
			[track release];
		}
	}
	for(i=0;i<[trackList count];i++) {
		XLDTrack *track = [trackList objectAtIndex:i];
		[[track metadata] setObject:[NSNumber numberWithInt:i+1] forKey:XLD_METADATA_TRACK];
		[[track metadata] setObject:[NSNumber numberWithInt:[trackList count]] forKey:XLD_METADATA_TOTALTRACKS];
		if(i==[trackList count]-1) [track setFrames:-1];
	}
	
	if(fseeko(fp,stblPos,SEEK_SET) != 0) goto end;
	
	while(1) { //skip until stsz;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"stsz",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	if(fseeko(fp,4,SEEK_CUR) != 0) goto end;
	if(fread(&tmp,4,1,fp) < 1) goto end;
	tmp = NSSwapBigIntToHost(tmp);
	if(tmp != 0) {
		for(i=0;i<[trackList count];i++) {
			[sampleSizeList addObject:[NSNumber numberWithInt:tmp]];
		}
	}
	else {
		if(fread(&entries,4,1,fp) < 1) goto end;
		entries = NSSwapBigIntToHost(entries);
		for(i=0;i<entries;i++) {
			if(fread(&tmp,4,1,fp) < 1) goto end;
			tmp = NSSwapBigIntToHost(tmp);
			[sampleSizeList addObject:[NSNumber numberWithInt:tmp]];
		}
	}
	if([sampleSizeList count] != [trackList count]) goto end;
	
	if(fseeko(fp,stblPos,SEEK_SET) != 0) goto end;
	
	while(1) { //skip until stco;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"stco",4)) break;
		if(fseeko(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	if(fseeko(fp,8,SEEK_CUR) != 0) goto end;
	if(fread(&tmp,4,1,fp) < 1) goto end;
	tmp = NSSwapBigIntToHost(tmp);
	if(fseeko(fp,tmp,SEEK_SET) != 0) goto end;
	for(i=0;i<[sampleSizeList count];i++) {
		off_t samplePos = ftello(fp);
		unsigned short length;
		unsigned short bom = 0;
		if(fread(&length,2,1,fp) < 1) goto end;
		length = NSSwapBigShortToHost(length);
		if(length > 2) {
			if(fread(&bom,2,1,fp) < 1) goto end;
			if(fseeko(fp,-2,SEEK_CUR) != 0) goto end;
		}
		char *string = malloc(length);
		if(fread(string,1,length,fp) < length) goto end;
		@try {
			if(bom == 0xfeff || bom == 0xfffe) {
				NSString *title = [[NSString alloc] initWithBytes:string length:length encoding:NSUnicodeStringEncoding];
				[[[trackList objectAtIndex:i] metadata] setObject:title forKey:XLD_METADATA_TITLE];
				[title release];
			}
			else {
				NSString *title = [[NSString alloc] initWithBytes:string length:length encoding:NSUTF8StringEncoding];
				[[[trackList objectAtIndex:i] metadata] setObject:title forKey:XLD_METADATA_TITLE];
				[title release];
			}
		}
		@catch (NSException * e) {
			
		}
		free(string);
		if(fseeko(fp,samplePos,SEEK_SET) != 0) goto end;
		if(fseeko(fp,[[sampleSizeList objectAtIndex:i] intValue],SEEK_CUR) != 0) goto end;
	}
	
end:
	if(fseeko(fp,initPos,SEEK_SET) != 0) goto end;
	if([trackList count]) return trackList;
	return nil;
}

@implementation XLDAlacDecoder
		

+ (BOOL)canHandleFile:(char *)path
{
	ExtAudioFileRef infile;
	FSRef inputFSRef;
	FSPathMakeRef((UInt8 *)path,&inputFSRef,NULL);
	if(ExtAudioFileOpen(&inputFSRef, &infile) != noErr) return NO;
	AudioStreamBasicDescription fmt;
	UInt32 size = sizeof(fmt);
	if(ExtAudioFileGetProperty(infile, kExtAudioFileProperty_FileDataFormat, &size, &fmt) != noErr) {
		ExtAudioFileDispose(infile);
		return NO;
	}
	if(fmt.mFormatID != 'alac') {
		ExtAudioFileDispose(infile);
		return NO;
	}
	ExtAudioFileDispose(infile);
	return YES;
}

+ (BOOL)canLoadThisBundle
{
	if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_3 ) {
		return NO;
	}
	else return YES;
}

- (id)init
{
	[super init];
	file = NULL;
	error = NO;
	metadataDic = [[NSMutableDictionary alloc] init];
	srcPath = nil;
	return self;
}

- (BOOL)openFile:(char *)path
{
	FSRef inputFSRef;
	FSPathMakeRef((UInt8 *)path,&inputFSRef,NULL);
	if(ExtAudioFileOpen(&inputFSRef, &file) != noErr) return NO;
	AudioStreamBasicDescription inputFormat,outputFormat;
	UInt32 size = sizeof(inputFormat);
	if(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &inputFormat) != noErr) {
		ExtAudioFileDispose(file);
		file = NULL;
		error = YES;
		return NO;
	}
	SInt64 frames;
	size = sizeof(frames);
	if(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &frames) != noErr) {
		ExtAudioFileDispose(file);
		file = NULL;
		error = YES;
		return NO;
	}
	if(inputFormat.mFormatID != 'alac') {
		ExtAudioFileDispose(file);
		file = NULL;
		error = YES;
		return NO;
	}
	
	switch(inputFormat.mFormatFlags) {
	  case 1:
		bps = 2;
		break;
	  case 2:
		bps = 3;
		break;
	  case 3:
		bps = 3;
		break;
	  case 4:
		bps = 4;
		break;
	  default:
		ExtAudioFileDispose(file);
		file = NULL;
		error = YES;
		return NO;
	}
	
	channels = inputFormat.mChannelsPerFrame;
	samplerate = inputFormat.mSampleRate;
	totalFrames = frames;
	
	outputFormat = inputFormat;
	outputFormat.mFormatID = 'lpcm';
#ifdef _BIG_ENDIAN
	outputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsPacked;
#else
	outputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
#endif
	outputFormat.mBytesPerPacket = 4 * inputFormat.mChannelsPerFrame;
	outputFormat.mFramesPerPacket = 1;
	outputFormat.mBytesPerFrame = outputFormat.mBytesPerPacket;
	outputFormat.mChannelsPerFrame = inputFormat.mChannelsPerFrame;
	outputFormat.mBitsPerChannel = 32;
	
	size = sizeof(outputFormat);
	if(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, size, &outputFormat) != noErr) {
		ExtAudioFileDispose(file);
		file = NULL;
		error = YES;
		return NO;
	}
	
	/* try to read total frame count and tags... */
	FILE *fp = fopen(path,"rb");
	xldoffset_t totalFramesFromFile;
	
	totalFramesFromFile = getTotalFrames(fp);
	if(trackArray) [trackArray release];
	trackArray = getChapterTrackList(fp, samplerate);
	if(trackArray) [trackArray retain];
	
tag:
	fclose(fp);
	fp = fopen(path,"rb");
	int tmp;
	char atom[4];
	
	while(1) { //skip until moov;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"moov",4)) break;
		if(fseek(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	int moovSize = tmp;
	int read = 8;
	
	while(read < moovSize) { //skip until udta;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"udta",4)) goto tagExist;
		if(fseek(fp,tmp-8,SEEK_CUR) != 0) goto end;
		read += tmp;
	}
	goto end;
	
tagExist:
	
	if(fseek(fp,12,SEEK_CUR) != 0) goto end; //skip until hdlr;
	
	while(1) { //skip until ilst;
		if(fread(&tmp,4,1,fp) < 1) goto end;
		if(fread(atom,1,4,fp) < 4) goto end;
		tmp = NSSwapBigIntToHost(tmp);
		if(!memcmp(atom,"ilst",4)) break;
		if(fseek(fp,tmp-8,SEEK_CUR) != 0) goto end;
	}
	
	void *buf = malloc(tmp-8);
	if(fread(buf,1,tmp-8,fp) < tmp-8) goto end;
	
	NSData *dat = [NSData dataWithBytesNoCopy:buf length:tmp-8];
	
	int len = [dat length];
	int current = 0;
	int atomLength;
	int flag;
	while(current < len) {
		[dat getBytes:&atomLength range:NSMakeRange(current,4)];
		[dat getBytes:atom range:NSMakeRange(current+4,4)];
		atomLength = NSSwapBigIntToHost(atomLength);
		
		if(!memcmp("\251nam",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_TITLE];
			[str release];
		}
		else if(!memcmp("\251ART",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_ARTIST];
			[str release];
		}
		else if(!memcmp("aART",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_ALBUMARTIST];
			[str release];
		}
		else if(!memcmp("\251alb",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_ALBUM];
			[str release];
		}
		else if(!memcmp("\251cmt",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_COMMENT];
			[str release];
		}
		else if(!memcmp("\251lyr",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_LYRICS];
			[str release];
		}
		else if(!memcmp("\251wrt",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_COMPOSER];
			[str release];
		}
		else if(!memcmp("\251day",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_DATE];
			if([str length] > 3) {
				int year = [[str substringWithRange:NSMakeRange(0,4)] intValue];
				if(year >= 1000 && year < 3000) [metadataDic setObject:[NSNumber numberWithInt:year] forKey:XLD_METADATA_YEAR];
			}
			[str release];
		}
		else if(!memcmp("\251gen",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_GENRE];
			[str release];
		}
		else if(!memcmp("gnre",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 0) goto last;
			short genreCode;
			[dat getBytes:&genreCode range:NSMakeRange(current+24,2)];
			genreCode = NSSwapBigShortToHost(genreCode);
			if(genreCode <= sizeof(ID3v1GenreList)/sizeof(*ID3v1GenreList)) {
				[metadataDic setObject:[NSString stringWithUTF8String:ID3v1GenreList[genreCode-1]] forKey:XLD_METADATA_GENRE];
			}
		}
		else if(!memcmp("trkn",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 0) goto last;
			short track;
			short totaltracks;
			[dat getBytes:&track range:NSMakeRange(current+26,2)];
			[dat getBytes:&totaltracks range:NSMakeRange(current+28,2)];
			track = NSSwapBigShortToHost(track);
			totaltracks = NSSwapBigShortToHost(totaltracks);
			if(track > 0) [metadataDic setObject:[NSNumber numberWithInt:track] forKey:XLD_METADATA_TRACK];
			if(totaltracks > 0) [metadataDic setObject:[NSNumber numberWithInt:totaltracks] forKey:XLD_METADATA_TOTALTRACKS];
		}
		else if(!memcmp("disk",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 0) goto last;
			short disc;
			short totaldiscs;
			[dat getBytes:&disc range:NSMakeRange(current+26,2)];
			[dat getBytes:&totaldiscs range:NSMakeRange(current+28,2)];
			disc = NSSwapBigShortToHost(disc);
			totaldiscs = NSSwapBigShortToHost(totaldiscs);
			if(disc > 0) [metadataDic setObject:[NSNumber numberWithInt:disc] forKey:XLD_METADATA_DISC];
			if(totaldiscs > 0) [metadataDic setObject:[NSNumber numberWithInt:totaldiscs] forKey:XLD_METADATA_TOTALDISCS];
		}
		else if(!memcmp("covr",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 0xd && flag != 0xe) goto last;
			if(tmp <= 16) goto last;
			tmp = tmp - 16;
			NSData *imgData = [dat subdataWithRange:NSMakeRange(current+24,tmp)];
			[metadataDic setObject:imgData forKey:XLD_METADATA_COVER];
		}
		else if(!memcmp("cpil",atom,4)) {
			if(atomLength != 0x19) goto last;
			char tmp3;
			[dat getBytes:&tmp3 range:NSMakeRange(current+24,1)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			flag = NSSwapBigIntToHost(flag);
			if(flag != 0x15) goto last;
			if(tmp3 != 0) [metadataDic setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_COMPILATION];
		}
		else if(!memcmp("\251grp",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_GROUP];
			[str release];
		}
		else if(!memcmp("tmpo",atom,4)) {
			if(atomLength != 0x1a) goto last;
			unsigned short tmp2;
			[dat getBytes:&tmp2 range:NSMakeRange(current+24,2)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp2 = NSSwapBigShortToHost(tmp2);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 0x15) goto last;
			[metadataDic setObject:[NSNumber numberWithUnsignedShort:tmp2] forKey:XLD_METADATA_BPM];
		}
		else if(!memcmp("cprt",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_COPYRIGHT];
			[str release];
		}
		else if(!memcmp("pgap",atom,4)) {
			if(atomLength != 0x19) goto last;
			char tmp3;
			[dat getBytes:&tmp3 range:NSMakeRange(current+24,1)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			flag = NSSwapBigIntToHost(flag);
			if(flag != 0x15) goto last;
			if(tmp3 != 0) [metadataDic setObject:[NSNumber numberWithBool:YES] forKey:XLD_METADATA_GAPLESSALBUM];
		}
		else if(!memcmp("sonm",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_TITLESORT];
			[str release];
		}
		else if(!memcmp("soar",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_ARTISTSORT];
			[str release];
		}
		else if(!memcmp("soal",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_ALBUMSORT];
			[str release];
		}
		else if(!memcmp("soaa",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_ALBUMARTISTSORT];
			[str release];
		}
		else if(!memcmp("soco",atom,4)) {
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			[dat getBytes:&flag range:NSMakeRange(current+16,4)];
			tmp = NSSwapBigIntToHost(tmp);
			flag = NSSwapBigIntToHost(flag);
			if(flag != 1) goto last;
			if(tmp <= 16) goto last;
			NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+24,tmp-16)] encoding:NSUTF8StringEncoding];
			if(!str) goto last;
			[metadataDic setObject:str forKey:XLD_METADATA_COMPOSERSORT];
			[str release];
		}
		else if(!memcmp("----",atom,4)) {
			int offset = 0;
			[dat getBytes:&tmp range:NSMakeRange(current+8,4)];
			tmp = NSSwapBigIntToHost(tmp);
			if(tmp <= 12) goto last;
			NSString *meanStr = [[[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+20,tmp-12)] encoding:NSUTF8StringEncoding] autorelease];
			if(!meanStr || ![meanStr isEqualToString:@"com.apple.iTunes"]) goto last;
			offset = tmp;
			
			[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
			tmp = NSSwapBigIntToHost(tmp);
			if(tmp <= 12) goto last;
			NSString *nameStr = [[[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+20,tmp-12)] encoding:NSUTF8StringEncoding] autorelease];
			if(!nameStr) goto last;
			offset += tmp;
			
			if([nameStr isEqualToString:@"iTunes_CDDB_1"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_GRACENOTE2];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicBrainz Track Id"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_MB_TRACKID];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicBrainz Album Id"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMID];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicBrainz Artist Id"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_MB_ARTISTID];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicBrainz Album Artist Id"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMARTISTID];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicBrainz Disc Id"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_MB_DISCID];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicIP PUID"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_PUID];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicBrainz Album Status"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMSTATUS];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicBrainz Album Type"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_MB_ALBUMTYPE];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicBrainz Album Release Country"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_MB_RELEASECOUNTRY];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicBrainz Release Group Id"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_MB_RELEASEGROUPID];
				[str release];
			}
			else if([nameStr isEqualToString:@"MusicBrainz Work Id"]) {
				[dat getBytes:&tmp range:NSMakeRange(current+offset+8,4)];
				[dat getBytes:&flag range:NSMakeRange(current+offset+16,4)];
				tmp = NSSwapBigIntToHost(tmp);
				flag = NSSwapBigIntToHost(flag);
				if(flag != 1) goto last;
				if(tmp <= 16) goto last;
				NSString *str = [[NSString alloc] initWithData:[dat subdataWithRange:NSMakeRange(current+offset+24,tmp-16)] encoding:NSUTF8StringEncoding];
				if(!str) goto last;
				[metadataDic setObject:str forKey:XLD_METADATA_MB_WORKID];
				[str release];
			}
		}
last:
		current += atomLength;
	}
	
end:
	fclose(fp);
	
	if(totalFramesFromFile > 0) totalFrames = totalFramesFromFile;
	//fprintf(stderr,"totalSamples: %lld\n",totalFrames);
	
	if(srcPath) [srcPath release];
	srcPath = [[NSString alloc] initWithUTF8String:path];
	return YES;
}

- (void)dealloc
{
	if(file) ExtAudioFileDispose(file);
	[metadataDic release];
	if(srcPath) [srcPath release];
	if(trackArray) [trackArray release];
	[super dealloc];
}

- (int)samplerate
{
	return samplerate;
}

- (int)bytesPerSample
{
	return bps;
}

- (int)channels
{
	return channels;
}

- (xldoffset_t)totalFrames
{
	return totalFrames;
}

- (int)isFloat
{
	return 0;
}

- (int)decodeToBuffer:(int *)buffer frames:(int)count
{
	UInt32 ret;
	UInt32 read = 0;
	fillBufList.mNumberBuffers = 1;
	fillBufList.mBuffers[0].mNumberChannels = channels;
	while(read < count) {
		fillBufList.mBuffers[0].mDataByteSize = (count-read)*4*channels;
		fillBufList.mBuffers[0].mData = buffer+read*channels;
		ret = count-read;
		int err = ExtAudioFileRead (file, &ret, &fillBufList);
		if(err != noErr) {
			//NSLog(@"ExtAudioFileRead error %d, %08x",err,err);
			error = YES;
			return 0;
		}
		//NSLog(@"req=%d read=%d",count,ret);
		if(ret == 0) break;
		read += ret;
	}
	
	return read;
}

- (xldoffset_t)seekToFrame:(xldoffset_t)count
{
	if(ExtAudioFileSeek(file,count) != noErr) {
		error = YES;
		return 0;
	}
	return count;
}

- (void)closeFile
{
	if(file) ExtAudioFileDispose(file);
	file = NULL;
	[metadataDic removeAllObjects];
	if(srcPath) [srcPath release];
	srcPath = nil;
	if(trackArray) [trackArray release];
	trackArray = nil;
	error = NO;
}

- (BOOL)error
{
	return error;
}

- (XLDEmbeddedCueSheetType)hasCueSheet
{
	if(trackArray) return XLDTrackTypeCueSheet;
	return XLDNoCueSheet;
}

- (id)cueSheet
{
	return trackArray;
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