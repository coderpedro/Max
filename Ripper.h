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

#import <Cocoa/Cocoa.h>

#import "Task.h"
#import "Track.h"

#include "cdparanoia/interface/cdda_interface.h"
#include "cdparanoia/paranoia/cdda_paranoia.h"

@interface Ripper : Task 
{
	Task					*_delegate;

	cdrom_paranoia			*_paranoia;
	cdrom_drive				*_drive;
	
	BOOL					_logActivity;
	
	int						_maximumRetries;
	
	NSArray					*_sectors;

	NSNumber				*_grandTotalSectors;
	NSNumber				*_sectorsRead;
	NSNumber				*_sectorsWritten;
	NSDate					*_startTime;
}

- (id)				initWithSectors:(NSArray *)sectors drive:(cdrom_drive *)drive;

- (void)			ripToFile:(int)file;

- (NSString *)		deviceName;

- (Task *)			delegate;
- (void)			setDelegate:(Task *)delegate;

@end
