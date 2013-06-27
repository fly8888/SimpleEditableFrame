// Copyright 2007-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AvailabilityMacros.h>
#import <TargetConditionals.h>
#import <Foundation/NSObjCRuntime.h>
#import <objc/runtime.h>
#import <objc/message.h>

#ifndef __has_feature
        #define __has_feature(x) 0 // Compatibility with non-clang compilers.
#endif

// These aren't defined in iPhone OS 3.2, but we want to use them unconditionally.
#if !defined(NS_RETURNS_RETAINED)
    #if defined(__clang__)
        #define NS_RETURNS_RETAINED __attribute__((ns_returns_retained))
    #else
        #define NS_RETURNS_RETAINED
    #endif
#endif

#import <CoreFoundation/CFBase.h>

#if !defined(CF_RETURNS_RETAINED)
    #if defined(__clang__)
        #define CF_RETURNS_RETAINED __attribute__((cf_returns_retained))
    #else
        #define CF_RETURNS_RETAINED
    #endif
#endif

#if !defined(CF_CONSUMED)
    #if __has_feature(attribute_cf_consumed)
        #define CF_CONSUMED __attribute__((cf_consumed))
    #else
        #define CF_CONSUMED
    #endif
#endif

// For use with OBJC_OLD_DISPATCH_PROTOTYPES=0 where we must cast objc_msgSend to a function pointer type

static inline void OBCallVoidIMP(IMP imp, id self, SEL _cmd)
{
    void (*f)(id, SEL) = (typeof(f))imp;
    f(self, _cmd);
}

static inline id OBCallObjectReturnIMP(IMP imp, id self, SEL _cmd)
{
    id (*f)(id, SEL) = (typeof(f))imp;
    return f(self, _cmd);
}

static inline void OBSendVoidMessage(id self, SEL _cmd)
{
    OBCallVoidIMP(objc_msgSend, self, _cmd);
}

static inline id OBSendObjectReturnMessage(id self, SEL _cmd)
{
    return OBCallObjectReturnIMP(objc_msgSend, self, _cmd);
}
