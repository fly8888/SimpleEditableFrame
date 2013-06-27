// Copyright 1997-2008, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSFileManager.h>

@interface NSFileManager (OFSimpleExtensions)

- (NSDictionary *)attributesOfItemAtPath:(NSString *)filePath traverseLink:(BOOL)traverseLink error:(NSError **)outError;

// Directory manipulations

- (BOOL)directoryExistsAtPath:(NSString *)path;
- (BOOL)directoryExistsAtPath:(NSString *)path traverseLink:(BOOL)traverseLink;

- (BOOL)createPathToFile:(NSString *)path attributes:(NSDictionary *)attributes error:(NSError **)outError;
// Creates any directories needed to be able to create a file at the specified path.

// Creates any directories needed to be able to create a file at the specified path.  Returns NO on failure.
- (BOOL)createPathComponents:(NSArray *)components attributes:(NSDictionary *)attributes error:(NSError **)outError;

// Instead of deleting in place, this moves the URL to a temporary location and then deletes it. This really only matters for directories, but this method doesn't try to check if the URL is a directory (since that is a race condition and would be slower anyway).
- (BOOL)atomicallyRemoveItemAtURL:(NSURL *)url error:(NSError **)outError;

// Changing file access/update timestamps.
- (BOOL)touchItemAtURL:(NSURL *)url error:(NSError **)outError;

#ifdef DEBUG
- (void)logPropertiesOfTreeAtURL:(NSURL *)url;
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (BOOL)addExcludedFromBackupAttributeToItemAtPath:(NSString *)path error:(NSError **)error;
#endif

@end

