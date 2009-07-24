/*
 *  $Id$
 *
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
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

#import "CompactDisc.h"

#import "Drive.h"
#import "LogController.h"

#include <discid/discid.h>
#include <IOKit/storage/IOCDTypes.h>

@implementation CompactDisc

- (id) initWithDeviceName:(NSString *)deviceName;
{
	if((self = [super init])) {
		unsigned				i;
		unsigned				session			= 1;
		unsigned long			discLength		= 150;
		Drive					*drive			= nil;
		TrackDescriptor			*track			= nil;
		NSMutableDictionary		*trackInfo		= nil;
		NSString				*ISRC			= nil;

		_deviceName		= [deviceName retain];

		// To avoid keeping an open file descriptor, read the disc's properties from the drive
		// and store them in our ivars
		drive = [[Drive alloc] initWithDeviceName:[self deviceName]];

		// Is this is a multisession disc?
		if([drive lastSession] - [drive firstSession] > 0)
			[LogController logMessage:NSLocalizedStringFromTable(@"Multisession disc detected", @"Log", @"")];
		
		// Use first session for now
		session			= 1;
		
		// Disc information
		_firstSector	= [drive firstSectorForSession:session];
		_lastSector		= [drive lastSectorForSession:session];

		_leadOut		= [drive leadOutForSession:session];

		_MCN			= [[drive readMCN] retain];
		
		// Iterate through the tracks and get their information
		_tracks			= [[NSMutableArray alloc] init];
		
		for(i = [drive firstTrackForSession:session]; i <= [drive lastTrackForSession:session]; ++i) {

			track = [drive trackNumber:i];
			
			trackInfo = [NSMutableDictionary dictionaryWithCapacity:6];
		
			[trackInfo setObject:[NSNumber numberWithUnsignedInt:i] forKey:@"number"];

			[trackInfo setObject:[NSNumber numberWithUnsignedInt:[drive firstSectorForTrack:i]] forKey:@"firstSector"];
			[trackInfo setObject:[NSNumber numberWithUnsignedInt:[drive lastSectorForTrack:i]] forKey:@"lastSector"];

			[trackInfo setObject:[NSNumber numberWithUnsignedInt:[track channels]] forKey:@"channels"];

			[trackInfo setObject:[NSNumber numberWithBool:[track preEmphasis]] forKey:@"preEmphasis"];
			[trackInfo setObject:[NSNumber numberWithBool:[track copyPermitted]] forKey:@"allowsDigitalCopy"];
			[trackInfo setObject:[NSNumber numberWithBool:[track dataTrack]] forKey:@"dataTrack"];

			ISRC = [drive readISRC:i];
			if(nil != ISRC)
				[trackInfo setObject:ISRC forKey:@"ISRC"];

			[_tracks addObject:trackInfo];
		}
		
		for(i = 0; i < [self countOfTracks]; ++i)
			discLength += [self lastSectorForTrack:i] - [self firstSectorForTrack:i] + 1;
		_length = (unsigned) (60 * (discLength / (60 * 75))) + (unsigned)((discLength / 75) % 60);
		
		[drive release];
				
		return self;
	}
	
	return nil;
}

- (void) dealloc
{
	[_deviceName release];		_deviceName = nil;
	[_tracks release];			_tracks = nil;
	[_MCN release];				_MCN = nil;

	[super dealloc];
}

- (NSString *)		deviceName								{ return [[_deviceName retain] autorelease]; }

- (NSString *)		MCN										{ return [[_MCN retain] autorelease]; }

- (unsigned)		firstSector								{ return _firstSector; }
- (unsigned)		lastSector								{ return _lastSector; }

- (unsigned)		leadOut									{ return _leadOut; }

- (unsigned)		firstSectorForTrack:(unsigned)track		{ return [[[self objectInTracksAtIndex:track] objectForKey:@"firstSector"] unsignedIntValue]; }
- (unsigned)		lastSectorForTrack:(unsigned)track		{ return [[[self objectInTracksAtIndex:track] objectForKey:@"lastSector"] unsignedIntValue]; }

- (unsigned)		channelsForTrack:(unsigned)track		{ return [[[self objectInTracksAtIndex:track] objectForKey:@"channels"] unsignedIntValue]; }

- (BOOL)			trackHasPreEmphasis:(unsigned)track		{ return [[[self objectInTracksAtIndex:track] objectForKey:@"hasPreEmphasis"] boolValue]; }
- (BOOL)			trackAllowsDigitalCopy:(unsigned)track	{ return [[[self objectInTracksAtIndex:track] objectForKey:@"allowsDigitalCopy"] boolValue]; }
- (BOOL)			trackContainsData:(unsigned)track		{ return [[[self objectInTracksAtIndex:track] objectForKey:@"dataTrack"] boolValue]; }

- (NSString *)		ISRCForTrack:(unsigned)track			{ return [[self objectInTracksAtIndex:track] objectForKey:@"ISRC"]; }

- (NSString *) discID
{
	NSString *musicBrainzDiscID = nil;
	
	DiscId *discID = discid_new();
	if(NULL == discID)
		return nil;
	
	// zero is lead out
	int offsets[100];
	offsets[0] = [self leadOut] + 150;
	
	unsigned i;
	for(i = 0; i < [self countOfTracks]; ++i)
		offsets[1 + i] = [self firstSectorForTrack:i] + 150;

	int result = discid_put(discID, 1, [self countOfTracks], offsets);
	if(result)
		musicBrainzDiscID = [NSString stringWithCString:discid_get_id(discID) encoding:NSASCIIStringEncoding];
		
	discid_free(discID);
	
	return [[musicBrainzDiscID retain] autorelease];
}

- (NSURL *) discIDSubmissionUrl
{
	NSURL *submissionUrl = nil;
	
	DiscId *discID = discid_new();
	if(NULL == discID)
		return nil;
	
	// zero is lead out
	int offsets[100];
	offsets[0] = [self leadOut] + 150;
	
	unsigned i;
	for(i = 0; i < [self countOfTracks]; ++i)
		offsets[1 + i] = [self firstSectorForTrack:i] + 150;
	
	int result = discid_put(discID, 1, [self countOfTracks], offsets);
	if(result)
		submissionUrl = [NSURL URLWithString:[NSString stringWithCString:discid_get_submission_url(discID) encoding:NSASCIIStringEncoding]];
	
	discid_free(discID);
	
	return [[submissionUrl retain] autorelease];
}

- (NSString *) freeDBDiscID
{
	NSString *freeDBDiscID = nil;
	
	DiscId *discID = discid_new();
	if(NULL == discID)
		return nil;
	
	// zero is lead out
	int offsets[100];
	offsets[0] = [self leadOut] + 150;
	
	unsigned i;
	for(i = 0; i < [self countOfTracks]; ++i)
		offsets[1 + i] = [self firstSectorForTrack:i] + 150;
	
	int result = discid_put(discID, 1, [self countOfTracks], offsets);
	if(result)
		freeDBDiscID = [NSString stringWithCString:discid_get_freedb_id(discID) encoding:NSASCIIStringEncoding];
	
	discid_free(discID);
	
	return [[freeDBDiscID retain] autorelease];
}

- (unsigned)		length									{ return _length; }

// KVC
- (unsigned)		countOfTracks							{ return [_tracks count]; }
- (NSDictionary *)	objectInTracksAtIndex:(unsigned)index	{ return [_tracks objectAtIndex:index]; }

@end
