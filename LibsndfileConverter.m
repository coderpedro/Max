/*
 *  $Id$
 *
 *  Copyright (C) 2005, 2006 Stephen F. Booth <me@sbooth.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import "LibsndfileConverter.h"

#import "MallocException.h"
#import "IOException.h"
#import "StopException.h"

#include <fcntl.h>		// open, write
#include <sys/stat.h>	// stat

@implementation LibsndfileConverter

- (id) initWithInputFilename:(NSString *)inputFilename
{
	SF_INFO					info;
	SF_FORMAT_INFO			formatInfo;

	if((self = [super initWithInputFilename:inputFilename])) {

		// Open the input file
		info.format = 0;
		
		_in = sf_open([_inputFilename UTF8String], SFM_READ, &info);
		if(NULL == _in) {
			@throw [IOException exceptionWithReason:[NSString stringWithFormat:@"Unable to open input sndfile (%i:%s)", sf_error(NULL), sf_strerror(NULL)] userInfo:nil];
		}
		
		// Get format info
		formatInfo.format = info.format;
		
		if(0 == sf_command(NULL, SFC_GET_FORMAT_INFO, &formatInfo, sizeof(formatInfo))) {
			_fileType = [[NSString stringWithUTF8String:formatInfo.name] retain];
		}
		else {
			_fileType = @"Unknown (libsndfile)";
		}
		
		return self;
	}
	return nil;
}

- (void) dealloc
{
	[_fileType release];
	sf_close(_in);
	
	[super dealloc];
}

- (oneway void) convertToFile:(int)file
{
	NSDate						*startTime			= [NSDate date];
	SNDFILE						*out				= NULL;
	SF_INFO						info;
	const char					*string				= NULL;
	int							i;
	int							err					= 0 ;
	int							bufferLen			= 1024 * 10;
	int							*intBuffer			= NULL;
	double						*doubleBuffer		= NULL;
	double						maxSignal;
	int							frameCount;
	int							readCount;
	unsigned long				iterations			= 0;
	
	// Tell our owner we are starting
	[_delegate setStartTime:startTime];	
	[_delegate setStarted];
	[_delegate setInputType:_fileType];
			
	// Setup libsndfile output file
	info.format			= SF_FORMAT_RAW | SF_FORMAT_PCM_16;
	info.samplerate		= 44100;
	info.channels		= 2;
	out					= sf_open_fd(file, SFM_WRITE, &info, 0);
	if(NULL == out) {
		[_delegate setStopped];
		@throw [IOException exceptionWithReason:[NSString stringWithFormat:@"Unable to create output sndfile (%i:%s)", sf_error(NULL), sf_strerror(NULL)] userInfo:nil];
	}
	
//	totalBytes		= sourceStat.st_size;
	
	// Copy metadata
	for(i = SF_STR_FIRST; i <= SF_STR_LAST; ++i) {
		string = sf_get_string(_in, i);
		if(NULL != string) {
			err = sf_set_string(out, i, string);
		}
	}
	
	// Copy audio data
	if(((info.format & SF_FORMAT_SUBMASK) == SF_FORMAT_DOUBLE) || ((info.format & SF_FORMAT_SUBMASK) == SF_FORMAT_FLOAT)) {
		
		doubleBuffer = (double *)malloc(bufferLen * sizeof(double));
		if(NULL == doubleBuffer) {
			[_delegate setStopped];
			@throw [MallocException exceptionWithReason:[NSString stringWithFormat:@"Unable to allocate memory (%i:%s) [%s:%i]", errno, strerror(errno), __FILE__, __LINE__] userInfo:nil];
		}
		
		frameCount		= bufferLen / info.channels ;
		readCount		= frameCount ;
		
		sf_command(_in, SFC_CALC_SIGNAL_MAX, &maxSignal, sizeof(maxSignal)) ;
		
		if(maxSignal < 1.0) {	
			while(readCount > 0) {
				// Check if we should stop, and if so throw an exception
				if(0 == iterations % MAX_DO_POLL_FREQUENCY && [_delegate shouldStop]) {
					[_delegate setStopped];
					@throw [StopException exceptionWithReason:@"Stop requested by user" userInfo:nil];
				}
				
				readCount = sf_readf_double(_in, doubleBuffer, frameCount) ;
				sf_writef_double(out, doubleBuffer, readCount) ;
				
				++iterations;
			}
		}
		// Renormalize output
		else {	
			sf_command(_in, SFC_SET_NORM_DOUBLE, NULL, SF_FALSE);
			
			while(0 < readCount) {
				// Check if we should stop, and if so throw an exception
				if(0 == iterations % MAX_DO_POLL_FREQUENCY && [_delegate shouldStop]) {
					[_delegate setStopped];
					@throw [StopException exceptionWithReason:@"Stop requested by user" userInfo:nil];
				}
				
				readCount = sf_readf_double(_in, doubleBuffer, frameCount);
				for(i = 0 ; i < readCount * info.channels; ++i) {
					doubleBuffer[i] /= maxSignal;
				}
				
				sf_writef_double(out, doubleBuffer, readCount);
				
				++iterations;
			}
		}
		
		free(doubleBuffer);
	}
	else {
		intBuffer = (int *)malloc(bufferLen * sizeof(int));
		if(NULL == intBuffer) {
			[_delegate setStopped];
			@throw [MallocException exceptionWithReason:[NSString stringWithFormat:@"Unable to allocate memory (%i:%s) [%s:%i]", errno, strerror(errno), __FILE__, __LINE__] userInfo:nil];
		}
		
		frameCount		= bufferLen / info.channels;
		readCount		= frameCount;
		
		while(0 < readCount) {	
			// Check if we should stop, and if so throw an exception
			if(0 == iterations % MAX_DO_POLL_FREQUENCY && [_delegate shouldStop]) {
				[_delegate setStopped];
				@throw [StopException exceptionWithReason:@"Stop requested by user" userInfo:nil];
			}
			
			readCount = sf_readf_int(_in, intBuffer, frameCount);
			sf_writef_int(out, intBuffer, readCount);
			
			++iterations;
		}
		
		free(intBuffer);
	}
		
	// Clean up sndfile
	sf_close(out);
	
	[_delegate setEndTime:[NSDate date]];
	[_delegate setCompleted];	
}

@end
