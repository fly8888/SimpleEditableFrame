// Copyright 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSRegularExpression-OFExtensions.h>
#import <OmniFoundation/OFRegularExpressionMatch.h>
#import <OmniFoundation/OFStringScanner.h>

RCS_ID("$Id$")

@implementation NSRegularExpression (OFExtensions)

- (OFRegularExpressionMatch *)of_firstMatchInString:(NSString *)string;
{
    return [self of_firstMatchInString:string range:NSMakeRange(0, [string length])];
}

- (OFRegularExpressionMatch *)of_firstMatchInString:(NSString *)string range:(NSRange)range;
{
    if (!string) // NSRegularExpression raises in this case, but apparently our old code didn't.
        
        return nil;
    
    NSTextCheckingResult *result = [self firstMatchInString:string options:0 range:range];
    if (!result)
        return nil;
    
    return [[[OFRegularExpressionMatch alloc] initWithTextCheckingResult:result string:string] autorelease];
}

- (BOOL)hasMatchInString:(NSString *)string;
{
    return [self firstMatchInString:string options:0 range:NSMakeRange(0, [string length])] != nil;
}

- (OFRegularExpressionMatch *)matchInScanner:(OFStringScanner *)stringScanner;
{
    OFRegularExpressionMatch *match = [self of_firstMatchInString:stringScanner.string range:stringScanner.remainingRange];
    if (!match)
        return nil;
    
    // Advance the scanner past the match
    stringScanner.scanLocation = NSMaxRange(match.matchRange);
    
    return match;
}

@end
