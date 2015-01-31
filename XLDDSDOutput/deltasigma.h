//
//  deltasigma.h
//  XLDDSDOutput
//
//  Created by tmkk on 15/01/24.
//
//	Copyright (c) 2015 tmkk <xld at tmkk.undo.jp> 
//
//	Permission is hereby granted, free of charge, to any person obtaining a copy
//	of this software and associated documentation files (the "Software"), to deal
//	in the Software without restriction, including without limitation the rights
//	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//	copies of the Software, and to permit persons to whom the Software is
//	furnished to do so, subject to the following conditions:
//
//	The above copyright notice and this permission notice shall be included in
//	all copies or substantial portions of the Software.
//
//	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//	THE SOFTWARE.

typedef enum
{
	DSMNoiseShaping2nd = 2,
	DSMNoiseShaping4th = 4,
	DSMNoiseShaping6th = 6,
	DSMNoiseShaping8th = 8,
} DSMNoiseShapingType;

typedef enum
{
	DSDFileFormatDSF = 0,
	DSDFileFormatDSDIFF = 1
} DSDFileFormat;

typedef struct _xld_deltasigma_t
{
	double *buffer;
	unsigned int idx;
	unsigned int bitBufMeter;
	unsigned int bitBuf;
	int (*modulate)(struct _xld_deltasigma_t*, const float*, unsigned char*, int, int);
	int (*finalize)(struct _xld_deltasigma_t*, unsigned char*);
} xld_deltasigma_t;

xld_deltasigma_t *deltasigma_init(DSDFileFormat format, DSMNoiseShapingType type);
void deltasigma_free(xld_deltasigma_t *dsm);
