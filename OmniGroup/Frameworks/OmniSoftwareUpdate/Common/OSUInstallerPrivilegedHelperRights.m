// Copyright 2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUInstallerPrivilegedHelperRights.h"

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

NSString * const OSUInstallUpdateRightName = @"com.omnigroup.OmniSoftwareUpdate.InstallUpdate";

static NSString * const OSUInstallerRightNameKey = @"OSUInstallerRightName";
static NSString * const OSUInstallerRightDefaultKey = @"OSUInstallerRightDefault";
static NSString * const OSUInstallerRightDescriptionKey = @"OSUInstallerRightDescription";

// The lookup keys that we need to pass to the Authorization APIs
static NSString * const OSUInstallUpdateDescription = @"Omni Software Update is trying to install an update.";

// The strings that we need to localize into our .strings files
#if 0
NSLocalizedStringFromTableInBundle(@"Omni Software Update is trying to install an update.", @"OSUInstallerRights", [NSBundle mainBundle], @"prompt shown when user is required to authorize to get to install a software update")
#endif

#pragma mark -

static NSArray * OSUInstallerAuthoriziationRights(void)
{
    static NSArray *authorizationRights = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        NSArray *rights = @[
            @{
                OSUInstallerRightNameKey : OSUInstallUpdateRightName,
                OSUInstallerRightDescriptionKey : OSUInstallUpdateDescription,
                OSUInstallerRightDefaultKey : @{
                    @"rule" : @[
                        @(kAuthorizationRuleAuthenticateAsAdmin),
                    ],
                    @"timeout" : @(300),
                },
            }
        ];
        authorizationRights = [rights copy];
    });

    return authorizationRights;
}


void OSUInstallerSetUpAuthorizationRights(void)
{
    OSStatus status = noErr;
    AuthorizationRef authRef = NULL;

    // Create our connection to the authorization system.
    // If we can't create an authorization reference then the app is not going to be able to do anything requiring authorization.
    
    status = AuthorizationCreate(NULL, NULL, 0, &authRef);
    NSCAssert(status == errAuthorizationSuccess, @"Could not connect to Authorization subsystem.");
    if (status != errAuthorizationSuccess) {
        NSLog(@"AuthorizationCreate failed with (%d).", status);
        return;
    }
    
    NSArray *rightsArray = OSUInstallerAuthoriziationRights();
    for (NSDictionary *right in rightsArray) {
        // Attempt to get the right. If we get back errAuthorizationDenied that means there's no current definition, so we add our default one.
        NSString *authRightName = right[OSUInstallerRightNameKey];
        NSString *authRightDefault = right[OSUInstallerRightDefaultKey];
        NSString *authRightDescription = right[OSUInstallerRightDescriptionKey];

        status = AuthorizationRightGet([authRightName UTF8String], NULL);
        if (status == errAuthorizationDenied) {
            status = AuthorizationRightSet(authRef, [authRightName UTF8String], (CFTypeRef)authRightDefault, (CFStringRef)authRightDescription,  NULL, CFSTR("OSUInstallerRights"));
            if (status != errAuthorizationSuccess) {
                NSLog(@"AuthorizationRightSet failed with (%d).", status);
            }
        } else {
            // If a right already exists (status == noErr) or any other error occurs, we assume that it has been set up in advance by the system administrator or this is the second time we've run.
            // Either way, there's nothing more for us to do.
        }
    }
    
    status = AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    NSCAssert(status == errAuthorizationSuccess, @"Error freeing authorization token.");
    (void)(status);
}

