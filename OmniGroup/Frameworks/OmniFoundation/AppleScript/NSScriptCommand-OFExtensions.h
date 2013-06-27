// Copyright 2006-2007, 2010, 2012 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSScriptCommand.h>

@class NSError;

@interface NSScriptCommand (OFExtensions)

- (NSScriptObjectSpecifier *)directParameterSpecifier;
- (NSScriptObjectSpecifier *)subjectSpecifier;

- (id)evaluatedSubjects; // Like -evaluatedReceivers, if the subject parameter of the original event was an object specifier, and that object specifier can be (or already has been) evaluated successfully, return the specified object(s).  Return nil otherwise.

- (void)setScriptError:(NSError *)error;

- (NSArray *)collectFlattenedObjectsFromArguments:(id)arguments requiringClass:(Class)cls arraySpecified:(BOOL *)outArraySpecified;
- (NSArray *)collectFlattenedObjectsFromArguments:(id)arguments requiringClass:(Class)cls;
- (NSArray *)collectFlattenedParametersRequiringClass:(Class)cls;

@end
