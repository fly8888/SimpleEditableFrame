// Copyright 2006-2008, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRelativeDateParser.h>

#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFErrors.h>

#import <Foundation/NSDateFormatter.h>
#import <Foundation/NSRegularExpression.h>
#import <OmniFoundation/NSRegularExpression-OFExtensions.h>
#import <OmniFoundation/OFRegularExpressionMatch.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>

#import "OFRelativeDateParser-Internal.h"

RCS_ID("$Id$");

// http://userguide.icu-project.org/strings/regexp
// http://icu.sourceforge.net/userguide/formatDateTime.html

static NSDictionary *relativeDateNames;
static NSDictionary *specialCaseTimeNames;
static NSDictionary *codes;
static NSDictionary *englishCodes;
static NSDictionary *modifiers;

static const unsigned unitFlags = NSSecondCalendarUnit | NSMinuteCalendarUnit | NSHourCalendarUnit | NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit | NSEraCalendarUnit;

static OFRelativeDateParser *sharedParser;

// english 
static NSArray *englishWeekdays;
static NSArray *englishShortdays;

#if 0 && defined(DEBUG)
    #define DEBUG_DATE(format, ...) NSLog(@"DATE: " format , ## __VA_ARGS__)
#else
    #define DEBUG_DATE(format, ...) do {} while (0)
#endif

typedef enum {
    DPHour = 0,
    DPDay = 1,
    DPWeek = 2,
    DPMonth = 3,
    DPYear = 4,
} DPCode;

typedef enum {
    OFRelativeDateParserNoRelativity = 0, // no modfier 
    OFRelativeDateParserCurrentRelativity = 2, // "this"
    OFRelativeDateParserFutureRelativity = -1, // "next"
    OFRelativeDateParserPastRelativity = 1, // "last"
} OFRelativeDateParserRelativity;

static NSRegularExpression *_createRegex(NSString *pattern)
{
    NSError *error;
    NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:pattern options:0 error:&error];
    if (!regex) {
        NSLog(@"Error creating regular expression from pattern: %@ --> %@", pattern, [error toPropertyList]);
    }
    return regex;
}

static NSCalendar *_defaultCalendar(void)
{
    // Not caching in case the time zone changes.
    NSCalendar *calendar = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] autorelease];
    [calendar setTimeZone:[NSTimeZone localTimeZone]];
    return calendar;
}

@interface OFRelativeDateParser (/*Private*/)
- (int)_multiplierForModifer:(int)modifier;
- (NSUInteger)_monthIndexForString:(NSString *)token;
- (NSUInteger)_weekdayIndexForString:(NSString *)token;
- (NSDate *)_modifyDate:(NSDate *)date withWeekday:(NSUInteger)requestedWeekday withModifier:(OFRelativeDateParserRelativity)modifier calendar:(NSCalendar *)calendar;
- (void)_addToComponents:(NSDateComponents *)components codeString:(DPCode)dpCode codeInt:(int)codeInt withMultiplier:(int)multiplier;
- (NSInteger)_determineYearForMonth:(NSUInteger)month withModifier:(OFRelativeDateParserRelativity)modifier fromCurrentMonth:(NSUInteger)currentMonth fromGivenYear:(NSInteger)givenYear;
- (NSDateComponents *)_parseTime:(NSString *)timeString withDate:(NSDate *)date withTimeFormat:(NSString *)timeFormat calendar:(NSCalendar *)calendar;
- (NSDate *)_parseFormattedDate:(NSString *)dateString withDate:(NSDate *)date withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withseparator:(NSString *)separator calendar:(NSCalendar *)calendar;
- (DateSet)_dateSetFromArray:(NSArray *)dateComponents withPositions:(DatePosition)datePosition;
- (NSDate *)_parseDateNaturalLangauge:(NSString *)dateString withDate:(NSDate *)date timeSpecific:(BOOL *)timeSpecific useEndOfDuration:(BOOL)useEndOfDuration calendar:(NSCalendar *)calendar error:(NSError **)error;
- (BOOL)_stringMatchesTime:(NSString *)firstString optionalSecondString:(NSString *)secondString withTimeFormat:(NSString *)timeFormat;
- (BOOL)_stringIsNumber:(NSString *)string;

// This group of methods (class and instance) normalize strings for scanning and matching user input.
// We use this to normalize localized strings and user input so that users can type ASCII-equivalent values and still get the benefit of the natural language parser
// See <bug:///73212>

enum {
    OFRelativeDateParserNormalizeOptionsDefault = (OFStringNormlizationOptionLowercase | OFStringNormilzationOptionStripCombiningMarks),
    OFRelativeDateParserNormalizeOptionsAbbreviations = (OFRelativeDateParserNormalizeOptionsDefault | OFStringNormilzationOptionStripPunctuation)
};

+ (NSDictionary *)_dictionaryByNormalizingKeysInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options locale:(NSLocale *)locale;;
+ (NSDictionary *)_dictionaryByNormalizingValuesInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options locale:(NSLocale *)locale;;
+ (NSArray *)_arrayByNormalizingValuesInArray:(NSArray *)array options:(NSUInteger)options locale:(NSLocale *)locale;;

- (NSDictionary *)_dictionaryByNormalizingKeysInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options;
- (NSDictionary *)_dictionaryByNormalizingValuesInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options;
- (NSArray *)_arrayByNormalizingValuesInArray:(NSArray *)array options:(NSUInteger)options;

@end

@implementation OFRelativeDateParser
// creates a new relative date parser with your current locale
+ (OFRelativeDateParser *)sharedParser;
{
    if (!sharedParser) {
	sharedParser = [[OFRelativeDateParser alloc] initWithLocale:[NSLocale currentLocale]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(currentLocaleDidChange:) name:NSCurrentLocaleDidChangeNotification object:nil];
    }
    return sharedParser;
}

+ (void)currentLocaleDidChange:(NSNotification *)notification;
{
    [sharedParser setLocale:[NSLocale currentLocale]];
}

+ (void)initialize;
{
    OBINITIALIZE;
    specialCaseTimeNames = [NSDictionary dictionaryWithObjectsAndKeys:
			    @"$(START_END_OF_THIS_WEEK)", NSLocalizedStringFromTableInBundle(@"this week", @"OFDateProcessing", OMNI_BUNDLE, @"time, used for scanning user input. Do NOT add whitespace"),
			    @"$(START_END_OF_NEXT_WEEK)", NSLocalizedStringFromTableInBundle(@"next week", @"OFDateProcessing", OMNI_BUNDLE, @"time, used for scanning user input. Do NOT add whitespace"),
			    @"$(START_END_OF_LAST_WEEK)", NSLocalizedStringFromTableInBundle(@"last week", @"OFDateProcessing", OMNI_BUNDLE, @"time, used for scanning user input. Do NOT add whitespace"),
			    nil];
    specialCaseTimeNames = [[self _dictionaryByNormalizingKeysInDictionary:specialCaseTimeNames options:OFRelativeDateParserNormalizeOptionsDefault locale:[NSLocale currentLocale]] retain];

    // TODO: Can't do seconds offsets for day math due to daylight savings
    // TODO: Make this a localized .plist where it looks something like:
    /*
     "demain" = {day:1}
     "avant-hier" = {day:-2}
     */
    // array info: Code, Number, Relativitity, timeSpecific, monthSpecific, daySpecific
    relativeDateNames = [NSDictionary dictionaryWithObjectsAndKeys:
			 /* Specified Time, Use Current Time */
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:0], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"now", @"OFDateProcessing", OMNI_BUNDLE, @"now, used for scanning user input. Do NOT add whitespace"),
			 /* Specified Time*/
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPHour], [NSNumber numberWithInt:12], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"noon", @"OFDateProcessing", OMNI_BUNDLE, @"noon, used for scanning user input. Do NOT add whitespace"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPHour], [NSNumber numberWithInt:23], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"tonight", @"OFDateProcessing", OMNI_BUNDLE, @"tonight, used for scanning user input. Do NOT add whitespace"),
			 /* Use default time */
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:0], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"today", @"OFDateProcessing", OMNI_BUNDLE, @"today, used for scanning user input. Do NOT add whitespace"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:0], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"tod", @"OFDateProcessing", OMNI_BUNDLE, @"\"tod\" this should be an abbreviation for \"today\" that makes sense for the given language, used for scanning user input. Do NOT add whitespace"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"tomorrow", @"OFDateProcessing", OMNI_BUNDLE, @"tomorrow"), 
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"tom", @"OFDateProcessing", OMNI_BUNDLE, @"\"tom\" this should be an abbreviation for \"tomorrow\" that makes sense for the given language, used for scanning user input. Do NOT add whitespace"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserPastRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"yesterday", @"OFDateProcessing", OMNI_BUNDLE, @"yesterday, used for scanning user input. Do NOT add whitespace"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserPastRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"yes", @"OFDateProcessing", OMNI_BUNDLE, @"\"yes\" this should be an abbreviation for \"yesterday\" that makes sense for the given language, used for scanning user input. Do NOT add whitespace"),
			 /* use default day */
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPMonth], [NSNumber numberWithInt:0], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity],  [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"this month", @"OFDateProcessing", OMNI_BUNDLE, @"this month, used for scanning user input. Do NOT add whitespace"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPMonth], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"next month", @"OFDateProcessing", OMNI_BUNDLE, @"next month, used for scanning user input. Do NOT add whitespace"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPMonth], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserPastRelativity],  [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"last month", @"OFDateProcessing", OMNI_BUNDLE, @"last month, used for scanning user input. Do NOT add whitespace"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPYear], [NSNumber numberWithInt:0], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity],  [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"this year", @"OFDateProcessing", OMNI_BUNDLE, @"this year, used for scanning user input. Do NOT add whitespace"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPYear], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity],  [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"next year", @"OFDateProcessing", OMNI_BUNDLE, @"next year, used for scanning user input. Do NOT add whitespace"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPYear], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserPastRelativity],  [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"last year", @"OFDateProcessing", OMNI_BUNDLE, @"last year, used for scanning user input. Do NOT add whitespace"),
			 
			 nil];
    relativeDateNames = [[self _dictionaryByNormalizingKeysInDictionary:relativeDateNames options:OFRelativeDateParserNormalizeOptionsDefault locale:[NSLocale currentLocale]] retain];
    
    // short hand codes
    codes = [NSDictionary dictionaryWithObjectsAndKeys:
	     [NSNumber numberWithInt:DPHour], NSLocalizedStringFromTableInBundle(@"h", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for hour or hours, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPHour], NSLocalizedStringFromTableInBundle(@"hour", @"OFDateProcessing", OMNI_BUNDLE, @"hour, singular, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPHour], NSLocalizedStringFromTableInBundle(@"hours", @"OFDateProcessing", OMNI_BUNDLE, @"hours, plural, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPDay], NSLocalizedStringFromTableInBundle(@"d", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for day or days, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPDay], NSLocalizedStringFromTableInBundle(@"day", @"OFDateProcessing", OMNI_BUNDLE, @"day, singular, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPDay], NSLocalizedStringFromTableInBundle(@"days", @"OFDateProcessing", OMNI_BUNDLE, @"days, plural, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPWeek], NSLocalizedStringFromTableInBundle(@"w", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for week or weeks, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPWeek], NSLocalizedStringFromTableInBundle(@"week", @"OFDateProcessing", OMNI_BUNDLE, @"week, singular, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPWeek], NSLocalizedStringFromTableInBundle(@"weeks", @"OFDateProcessing", OMNI_BUNDLE, @"weeks, plural, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPMonth],NSLocalizedStringFromTableInBundle(@"m", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for month or months, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPMonth], NSLocalizedStringFromTableInBundle(@"month", @"OFDateProcessing", OMNI_BUNDLE, @"month, singular, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPMonth], NSLocalizedStringFromTableInBundle(@"months", @"OFDateProcessing", OMNI_BUNDLE, @"months, plural, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPYear], NSLocalizedStringFromTableInBundle(@"y", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for year or years, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPYear], NSLocalizedStringFromTableInBundle(@"year", @"OFDateProcessing", OMNI_BUNDLE, @"year, singular, used for scanning user input. Do NOT add whitespace"),
	     [NSNumber numberWithInt:DPYear], NSLocalizedStringFromTableInBundle(@"years", @"OFDateProcessing", OMNI_BUNDLE, @"years, plural, used for scanning user input. Do NOT add whitespace"),
	     nil];
    codes = [[self _dictionaryByNormalizingKeysInDictionary:codes options:OFRelativeDateParserNormalizeOptionsDefault locale:[NSLocale currentLocale]] retain];

    englishCodes = [[NSDictionary alloc] initWithObjectsAndKeys:
                    [NSNumber numberWithInt:DPHour], @"h",
                    [NSNumber numberWithInt:DPHour], @"hour",
                    [NSNumber numberWithInt:DPHour], @"hours",
                    [NSNumber numberWithInt:DPDay], @"d",
                    [NSNumber numberWithInt:DPDay], @"day",
                    [NSNumber numberWithInt:DPDay], @"days",
                    [NSNumber numberWithInt:DPWeek], @"w",
                    [NSNumber numberWithInt:DPWeek], @"week",
                    [NSNumber numberWithInt:DPWeek], @"weeks",
                    [NSNumber numberWithInt:DPMonth],@"m",
                    [NSNumber numberWithInt:DPMonth], @"month",
                    [NSNumber numberWithInt:DPMonth], @"months",
                    [NSNumber numberWithInt:DPYear], @"y",
                    [NSNumber numberWithInt:DPYear], @"year",
                    [NSNumber numberWithInt:DPYear], @"years",
                    nil];
    
    // time modifiers
    modifiers = [NSDictionary dictionaryWithObjectsAndKeys:
		 [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity], NSLocalizedStringFromTableInBundle(@"+", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, used for scanning user input. Do NOT add whitespace"),
		 [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity], NSLocalizedStringFromTableInBundle(@"next", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, the most commonly used translation of \"next\", or some other shorthand way of saying things like \"next week\", used for scanning user input. Do NOT add whitespace"),
		 [NSNumber numberWithInt:OFRelativeDateParserPastRelativity], NSLocalizedStringFromTableInBundle(@"-", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, used for scanning user input. Do NOT add whitespace"),
		 [NSNumber numberWithInt:OFRelativeDateParserPastRelativity], NSLocalizedStringFromTableInBundle(@"last", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, used for scanning user input. Do NOT add whitespace"),
		 [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], NSLocalizedStringFromTableInBundle(@"~", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, used for scanning user input. Do NOT add whitespace"),
		 [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], NSLocalizedStringFromTableInBundle(@"this", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, the most commonly used translation of \"this\", or some other shorthand way of saying things like \"this week\", used for scanning user input. Do NOT add whitespace"),
		 nil];
    modifiers = [[self _dictionaryByNormalizingKeysInDictionary:modifiers options:OFRelativeDateParserNormalizeOptionsDefault locale:[NSLocale currentLocale]] retain];
    
    // english 
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease]; 
    OBASSERT([formatter formatterBehavior] == NSDateFormatterBehavior10_4);
    NSLocale *en_US = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    [formatter setLocale:en_US];
    englishWeekdays = [[self _arrayByNormalizingValuesInArray:[formatter weekdaySymbols] options:OFRelativeDateParserNormalizeOptionsDefault locale:en_US] retain];
    englishShortdays = [[self _arrayByNormalizingValuesInArray:[formatter shortWeekdaySymbols] options:OFRelativeDateParserNormalizeOptionsDefault locale:en_US] retain];    
    [en_US release];
}

- initWithLocale:(NSLocale *)locale;
{
    if (!(self = [super init]))
        return nil;
    [self setLocale:locale];
    return self;
}

- (void) dealloc 
{
    [_locale release];
    [_weekdays release];
    [_shortdays release];
    [_alternateShortdays release];
    [_months release];
    [_shortmonths release];
    [_alternateShortmonths release];
    
    [super dealloc];
}

- (NSLocale *)locale;
{
    return _locale;
}

- (void)setLocale:(NSLocale *)locale;
{
    if (_locale != locale) {
	[_locale release];
	_locale = [locale retain];
	
	// Rebuild the weekday/month name arrays for a new locale
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        OBASSERT([formatter formatterBehavior] == NSDateFormatterBehavior10_4);
        
	[formatter setLocale:locale];
	
	[_weekdays release];
        _weekdays = [[self _arrayByNormalizingValuesInArray:[formatter weekdaySymbols] options:OFRelativeDateParserNormalizeOptionsDefault] retain];
	
	[_shortdays release];
        _shortdays = [[self _arrayByNormalizingValuesInArray:[formatter shortWeekdaySymbols] options:OFRelativeDateParserNormalizeOptionsDefault] retain];
	
        [_alternateShortdays release];
        _alternateShortdays = [[self _arrayByNormalizingValuesInArray:[formatter shortWeekdaySymbols] options:OFRelativeDateParserNormalizeOptionsAbbreviations] retain];
        
	[_months release];
        _months = [[self _arrayByNormalizingValuesInArray:[formatter monthSymbols] options:OFRelativeDateParserNormalizeOptionsDefault] retain];
	
	[_shortmonths release];
        _shortmonths = [[self _arrayByNormalizingValuesInArray:[formatter shortMonthSymbols] options:OFRelativeDateParserNormalizeOptionsDefault] retain];

	[_alternateShortmonths release];
        _alternateShortmonths = [[self _arrayByNormalizingValuesInArray:[formatter shortMonthSymbols] options:OFRelativeDateParserNormalizeOptionsAbbreviations] retain];
    }
    
}

- (BOOL)getDateValue:(NSDate **)date 
	   forString:(NSString *)string
   	       error:(NSError **)error;
{
    return [self getDateValue:date forString:string useEndOfDuration:NO defaultTimeDateComponents:nil calendar:nil error:error];
}

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents calendar:(NSCalendar *)calendar error:(NSError **)error;
{
    if (!calendar)
        calendar = _defaultCalendar();

    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease]; 
    OBASSERT([formatter formatterBehavior] == NSDateFormatterBehavior10_4);

    [formatter setCalendar:calendar];
    [formatter setLocale:_locale];
    
    [formatter setDateStyle:NSDateFormatterShortStyle]; 
    [formatter setTimeStyle:NSDateFormatterNoStyle]; 
    NSString *shortFormat = [[[formatter dateFormat] copy] autorelease];
    
    [formatter setDateStyle:NSDateFormatterMediumStyle]; 
    NSString *mediumFormat = [[[formatter dateFormat] copy] autorelease];
    
    [formatter setDateStyle:NSDateFormatterLongStyle]; 
    NSString *longFormat = [[[formatter dateFormat] copy] autorelease];
    
    [formatter setDateStyle:NSDateFormatterNoStyle]; 
    [formatter setTimeStyle:NSDateFormatterShortStyle]; 
    NSString *timeFormat = [[[formatter dateFormat] copy] autorelease]; 
    
    return [self getDateValue:date 
		    forString:string 
	     fromStartingDate:[NSDate date] 
                     calendar:calendar
	  withShortDateFormat:shortFormat
	 withMediumDateFormat:mediumFormat
	   withLongDateFormat:longFormat
	       withTimeFormat:timeFormat
	     useEndOfDuration:useEndOfDuration
    defaultTimeDateComponents:defaultTimeDateComponents
			error:error];
}

- (BOOL)getDateValue:(NSDate **)date 
	   forString:(NSString *)string 
    fromStartingDate:(NSDate *)startingDate 
            calendar:(NSCalendar *)calendar
 withShortDateFormat:(NSString *)shortFormat 
withMediumDateFormat:(NSString *)mediumFormat 
  withLongDateFormat:(NSString *)longFormat 
      withTimeFormat:(NSString *)timeFormat
	       error:(NSError **)error;
{
    return [self getDateValue:date 
		    forString:string 
	     fromStartingDate:startingDate 
                     calendar:calendar 
	  withShortDateFormat:shortFormat
	 withMediumDateFormat:mediumFormat
	   withLongDateFormat:longFormat
	       withTimeFormat:timeFormat
	     useEndOfDuration:NO
    defaultTimeDateComponents:nil // not needed for unit tests
			error:error];
}

- (BOOL)getDateValue:(NSDate **)date 
	   forString:(NSString *)string 
    fromStartingDate:(NSDate *)startingDate 
            calendar:(NSCalendar *)calendar
 withShortDateFormat:(NSString *)shortFormat 
withMediumDateFormat:(NSString *)mediumFormat 
  withLongDateFormat:(NSString *)longFormat 
      withTimeFormat:(NSString *)timeFormat
    useEndOfDuration:(BOOL)useEndOfDuration
defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents
 	       error:(NSError **)error;
{
    
    // return nil instead of the current date on empty string
    if ([NSString isEmptyString:string]) {
	date = nil;
	return YES;
    }
    
    if (!calendar)
        calendar = _defaultCalendar();
    
    string = [[string lowercaseString] stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
    NSString *dateString = nil;
    NSString *timeString = nil;
    
    // first see if we have an @, if so then we can easily split the date and time portions of the string
    string = [string stringByReplacingOccurrencesOfString:@" at " withString:@"@"];
    if ([string containsString:@"@"]) {
	
	NSArray *dateAndTime = [string componentsSeparatedByString:@"@"];
	
	if ([dateAndTime count] > 2) {
#ifdef DEBUG_xmas
#error this code needs a code in OFErrors -- zero is not valid
#endif
	    OFError(error, // error
		    0,  // code enum
		    @"accepted strings are of the form \"DATE @ TIME\", there was an extra \"@\" sign", // description
                    nil
		    );
	    
	    return NO;
	}
	
	// allow for the string to start with the time, and have no time, an "@" must always precede the time
	if ([string hasPrefix:@"@"]) {
	    DEBUG_DATE( @"string starts w/ an @ , so there is no date");
	    timeString = [dateAndTime objectAtIndex:1];
	} else {
	    dateString = [dateAndTime objectAtIndex:0];
	    if ([dateAndTime count] == 2) 
		timeString = [dateAndTime objectAtIndex:1];
	}
	DEBUG_DATE( @"contains @, dateString: %@, timeString: %@", dateString, timeString );
    } else {
	DEBUG_DATE(@"-----------'%@' starting date:%@", string, startingDate);
	NSArray *stringComponents = [string componentsSeparatedByString:@" "];
	NSUInteger maxComponentIndex = [stringComponents count] - 1;
	
	// test for a time at the end of the string.  This will only match things that are clearly times, ie, has colons, or am/pm
	NSInteger timeMatchIndex = -1;
	if ([self _stringMatchesTime:[stringComponents objectAtIndex:maxComponentIndex] optionalSecondString:nil withTimeFormat:timeFormat]) {
	    //DEBUG_DATE(@"returned a true for _stringMatchesTime and the previous thing WASN't A MONTH for the end of the string: %@", [stringComponents objectAtIndex:maxComponentIndex]);
	    timeMatchIndex = maxComponentIndex;
	} else if (maxComponentIndex >= 1 && [self _stringMatchesTime:[stringComponents objectAtIndex:maxComponentIndex-1] optionalSecondString:[stringComponents objectAtIndex:maxComponentIndex] withTimeFormat:timeFormat]) {
	    //DEBUG_DATE(@"returned a true for _stringMatchesTime for (with 2 comps): %@ & %@", [stringComponents objectAtIndex:maxComponentIndex-1], [stringComponents objectAtIndex:maxComponentIndex]);
	    timeMatchIndex = maxComponentIndex -1;
	} else if ([self _stringIsNumber:[stringComponents objectAtIndex:maxComponentIndex]]) {
	    int number = [[stringComponents objectAtIndex:maxComponentIndex] intValue];
	    int minutes = number % 100;
	    if (([timeFormat isEqualToString:@"HHmm"] || [timeFormat isEqualToString:@"kkmm"])&& ([[stringComponents objectAtIndex:maxComponentIndex] length] == 4)) {
		if (number < 2500 && minutes < 60) {
		    DEBUG_DATE(@"The time format is 24 hour time with the format: %@.  The number is: %d, and is less than 2500. The minutes are: %d, and are less than 60", timeFormat, number, minutes);
		    timeMatchIndex = maxComponentIndex;
		}
	    } 
	} 
	
	if (timeMatchIndex != -1) {
	    DEBUG_DATE(@"Time String found, the time match index is: %ld", timeMatchIndex);
	    if (maxComponentIndex == 0 && (unsigned)timeMatchIndex == 0) {
		//DEBUG_DATE(@"count = index = 0");
		timeString = string;
	    } else { 
		//DEBUG_DATE(@"maxComponentIndex: %d, timeMatchIndex: %d", maxComponentIndex, timeMatchIndex);
		NSArray *timeComponents = [stringComponents subarrayWithRange:NSMakeRange(timeMatchIndex, maxComponentIndex-timeMatchIndex+1)];
		timeString = [timeComponents componentsJoinedByString:@" "];
		NSArray *dateComponents = [stringComponents subarrayWithRange:NSMakeRange(0, timeMatchIndex)];
		dateString = [dateComponents componentsJoinedByString:@" "];
	    }
	} else {
	    dateString = string;
	}
	DEBUG_DATE( @"NO @, dateString: %@, timeString: %@", dateString, timeString );
    }
    
    BOOL timeSpecific = NO;
    
    if (![NSString isEmptyString:dateString]) {
        
        OFCreateRegularExpression(spacedDateRegex, @"^(\\d{1,4})\\s(\\d{1,4})\\s?(\\d{0,4})$");
        OFCreateRegularExpression(formattedDateRegex, @"^\\w+([\\./-])\\w+");
        OFCreateRegularExpression(unSeperatedDateRegex, @"^(\\d{2,4})(\\d{2})(\\d{2})$");
        
	OFRegularExpressionMatch *spacedDateMatch = [spacedDateRegex of_firstMatchInString:dateString];
	OFRegularExpressionMatch *formattedDateMatch = [formattedDateRegex of_firstMatchInString:dateString];
	OFRegularExpressionMatch *unSeperatedDateMatch = [unSeperatedDateRegex of_firstMatchInString:dateString];
	
	if (unSeperatedDateMatch) {
	    dateString = [NSString stringWithFormat:@"%@-%@-%@", [unSeperatedDateMatch captureGroupAtIndex:0], [unSeperatedDateMatch captureGroupAtIndex:1], [unSeperatedDateMatch captureGroupAtIndex:2]];
        }
	
	if (formattedDateMatch || unSeperatedDateMatch || spacedDateMatch) {
	    NSString *separator = @" ";
	    if (unSeperatedDateMatch) {
		DEBUG_DATE(@"found an 'unseperated' date");
		separator = @"-";
	    } else if (formattedDateMatch) {
		DEBUG_DATE(@"formatted date found with the seperator as: %@", [formattedDateMatch captureGroupAtIndex:0]);
		separator = [formattedDateMatch captureGroupAtIndex:0];
	    } else if (spacedDateMatch) {
		DEBUG_DATE(@"numerical space delimted date found");
		separator = @" ";
	    }
	    
	    *date = [self _parseFormattedDate:dateString withDate:startingDate withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withseparator:separator calendar:calendar];
	} else
	    *date = [self _parseDateNaturalLangauge:dateString withDate:startingDate timeSpecific:&timeSpecific useEndOfDuration:useEndOfDuration calendar:calendar error:error];
    } else
	*date = startingDate;
    
    if (timeString != nil)  
	*date = [calendar dateFromComponents:[self _parseTime:timeString withDate:*date withTimeFormat:timeFormat calendar:calendar]];
    else {
	static NSRegularExpression *hourCodeRegex = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSString *shortHourString = NSLocalizedStringFromTableInBundle(@"h", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for hour or hours, used for scanning user input. Do NOT add whitespace");
            NSString *hourString = NSLocalizedStringFromTableInBundle(@"hour", @"OFDateProcessing", OMNI_BUNDLE, @"hour, singular, used for scanning user input. Do NOT add whitespace");
            NSString *pluralHourString = NSLocalizedStringFromTableInBundle(@"hours", @"OFDateProcessing", OMNI_BUNDLE, @"hours, plural, used for scanning user input. Do NOT add whitespace");
            NSString *patternString = [NSString stringWithFormat:@"\\d+(%@|%@|%@|h|hour|hours)", shortHourString, hourString, pluralHourString];
            
            NSError *expressionError;
	    hourCodeRegex = [[NSRegularExpression alloc] initWithPattern:patternString options:0 error:&expressionError];
            if (!hourCodeRegex) {
                NSLog(@"Error creating regular expression: %@", [expressionError toPropertyList]);
            }
        });

	OFRegularExpressionMatch *hourCode = [hourCodeRegex of_firstMatchInString:string];
	if (!hourCode && *date && !timeSpecific) {
	    //DEBUG_DATE(@"no date information, and no hour codes, set to midnight");
	    NSDateComponents *defaultTime = [calendar components:NSDayCalendarUnit|NSMonthCalendarUnit|NSYearCalendarUnit|NSEraCalendarUnit fromDate:*date];
	    [defaultTime setHour:[defaultTimeDateComponents hour]];
	    [defaultTime setMinute:[defaultTimeDateComponents minute]];
	    [defaultTime setSecond:[defaultTimeDateComponents second]];
	    *date = [calendar dateFromComponents:defaultTime];
	}
    }
    DEBUG_DATE(@"Return date: %@", *date);
    //if (!*date) {
    //OBErrorWithInfo(&*error, "date parse error", @"GAH");  
    //return NO;
    //}
    return YES;
}

- (NSString *)stringForDate:(NSDate *)date withDateFormat:(NSString *)dateFormat withTimeFormat:(NSString *)timeFormat;
{
    
    return [self stringForDate:date withDateFormat:dateFormat withTimeFormat:timeFormat calendar:nil];
}

- (NSString *)stringForDate:(NSDate *)date withDateFormat:(NSString *)dateFormat withTimeFormat:(NSString *)timeFormat calendar:(NSCalendar *)calendar;
{
    if (!calendar)
        calendar = _defaultCalendar();

    NSDateComponents *components = [calendar components:unitFlags fromDate:date];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    OBASSERT([formatter formatterBehavior] == NSDateFormatterBehavior10_4); // Linked on 10.6
    
    [formatter setCalendar:calendar];
    [formatter setLocale:_locale];
    [formatter setDateFormat:dateFormat];
    
    if ([components hour] != NSUndefinedDateComponent) 
	[formatter setDateFormat:[[dateFormat stringByAppendingString:@" "] stringByAppendingString:timeFormat]];
    NSString *result = [formatter stringFromDate:date];
    [formatter release];

    return result;
}

#pragma mark -
#pragma mark Private

- (BOOL)_stringIsNumber:(NSString *)string;
{
    //test for just a single number, note that [NSString intValue] won't work since it returns 0 on failure, and 0 is an allowed number
    OFCreateRegularExpression(numberRegex, @"^(\\d*)$");
    OFRegularExpressionMatch *numberMatch = [numberRegex of_firstMatchInString:string];
    return (numberMatch != nil);
}

- (BOOL)_stringMatchesTime:(NSString *)firstString optionalSecondString:(NSString *)secondString withTimeFormat:(NSString *)timeFormat;
{
    if (secondString) {
	if (!(([secondString hasPrefix:@"a"] || [secondString hasPrefix:@"p"]) && [secondString length] <= 2)) 
	    return NO;
	
	if ([self _stringIsNumber:firstString])
	    return YES;
    }

    // see if we have a european date
    OFCreateRegularExpression(timeDotRegex, @"^(\\d{1,2})\\.(\\d{1,2})\\.?(\\d{0,2})$");
    OFCreateRegularExpression(timeFormatDotRegex, @"[HhkK]'?\\.'?[m]");
    OFRegularExpressionMatch *dotMatch = [timeDotRegex of_firstMatchInString:firstString];
    OFRegularExpressionMatch *timeFormatDotMatch = [timeFormatDotRegex of_firstMatchInString:timeFormat];
    if (dotMatch&&timeFormatDotMatch)
	return YES;
    
    // see if we have some colons in a dately way
    OFCreateRegularExpression(timeColonRegex, @"^(\\d{1,2}):(\\d{0,2}):?(\\d{0,2})");
    OFRegularExpressionMatch *colonMatch = [timeColonRegex of_firstMatchInString:firstString];
    if (colonMatch)
	return YES;
    
    // see if we match a meridan at the end of our string
    OFCreateRegularExpression(timeEndRegex, @"\\d[apAP][mM]?$");
    OFRegularExpressionMatch *timeEndMatch = [timeEndRegex of_firstMatchInString:firstString];
    if (timeEndMatch)
	return YES;
    
    return NO;
}

- (NSDateComponents *)_parseTime:(NSString *)timeString withDate:(NSDate *)date withTimeFormat:(NSString *)timeFormat calendar:(NSCalendar *)calendar;
{
    timeString = [timeString stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
    NSScanner *timeScanner = [NSScanner localizedScannerWithString:timeString];
    [timeScanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
    
    NSString *timeToken = nil; // this will be all of the string until we get to letters, i.e. am/pm
    BOOL isPM = NO; // TODO: Make a default.
    [timeScanner scanUpToCharactersFromSet:[NSCharacterSet letterCharacterSet] intoString:&timeToken];
    [timeScanner setCaseSensitive:NO];
    while (![timeScanner isAtEnd]) {
	if ([timeScanner scanString:@"p" intoString:NULL]) {
	    isPM = YES;
	    break;
	} else if ([timeScanner scanString:@"a" intoString:NULL]) {
	    isPM = NO;
	    break;
	} else
	    [timeScanner setScanLocation:[timeScanner scanLocation]+1];
	
	
	// note to self: do I need this? I think I don't, and that I'm missing the last char
	if ([timeScanner scanLocation] == [[timeScanner string] length])
	    break;
    }
    
    static dispatch_once_t onceToken;
    static NSRegularExpression *timeSeperatorRegex = nil;
    dispatch_once(&onceToken, ^{
	timeSeperatorRegex = _createRegex(@"^\\d{1,4}([:.])?");
    });
    OFRegularExpressionMatch *timeSeperatorMatch = [timeSeperatorRegex of_firstMatchInString:timeToken];
    DEBUG_DATE(@"timeSeperatorMatch = %@", timeSeperatorMatch);
    NSString *seperator = [timeSeperatorMatch captureGroupAtIndex:0];
    if ([NSString isEmptyString:seperator])
	seperator = @":";
    
    NSArray *timeComponents = [[timeToken stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace] componentsSeparatedByString:seperator];
    DEBUG_DATE( @"TimeToken: %@, isPM: %d", timeToken, isPM);
    DEBUG_DATE(@"time comps: %@", timeComponents);
    
    int hours = -1;
    int minutes = -1;
    int seconds = -1;
    unsigned int timeMarker;
    for (timeMarker = 0; timeMarker < [timeComponents count]; ++timeMarker) {
	switch (timeMarker) {
	    case 0:
		hours = [[timeComponents objectAtIndex:timeMarker] intValue];
		break;
	    case 1:
		minutes = [[timeComponents objectAtIndex:timeMarker] intValue];
		break;
	    case 2:
		seconds = [[timeComponents objectAtIndex:timeMarker] intValue];
		break;
	}
    }
    if (isPM && hours < 12) {
	DEBUG_DATE(@"isPM was true, adding 12 to: %d", hours);
	hours += 12;
    }  else if ([[timeComponents objectAtIndex:0] length] == 4 && [timeComponents count] == 1 && hours <= 2500 ) {
	//24hour time
	minutes = hours % 100;
	hours = hours / 100;
	DEBUG_DATE(@"time in 4 digit notation");
    } else if (![timeFormat hasPrefix:@"H"] && ![timeFormat hasPrefix:@"k"] && hours == 12 && !isPM) {
	DEBUG_DATE(@"time format doesn't have 'H', at 12 hours, setting to 0");
	hours = 0;
    }
    
    // if 1-24 "k" format, then 24 means 0
    if ([timeFormat hasPrefix:@"k"]) { 
	if (hours == 24) {
	    DEBUG_DATE(@"time format has 'k', at 24 hours, setting to 0");
	    hours = 0;
	}
	
    }
    DEBUG_DATE( @"hours: %d, minutes: %d, seconds: %d", hours, minutes, seconds );
    if (hours == -1)
	return nil;
    
    NSDateComponents *components = [calendar components:unitFlags fromDate:date];
    if (seconds != -1)
	[components setSecond:seconds];
    else
	[components setSecond:0];
    
    if (minutes != -1) 
	[components setMinute:minutes];
    else
	[components setMinute:0];
    
    if (hours != -1)
	[components setHour:hours];
    
    return components;
}

- (NSDate *)_parseFormattedDate:(NSString *)dateString withDate:(NSDate *)date withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withseparator:(NSString *)separator calendar:(NSCalendar *)calendar;
{
    OBPRECONDITION(calendar);
    
    DEBUG_DATE(@"parsing formatted dateString: %@", dateString );
    NSDateComponents *currentComponents = [calendar components:unitFlags fromDate:date]; // the given date as components
    
    OBASSERT(separator);
    NSMutableArray *dateComponents = [NSMutableArray arrayWithArray:[dateString componentsSeparatedByString:separator]];
    if ([NSString isEmptyString:[dateComponents lastObject]]) 
	[dateComponents removeLastObject];
    
    DEBUG_DATE(@"determined date componets as: %@", dateComponents);
    
    NSString *dateFormat = shortFormat;
    OFCreateRegularExpression(mediumMonthRegex, @"[a-z]{3}");
    OFRegularExpressionMatch *mediumMonthMatch = [mediumMonthRegex of_firstMatchInString:dateString];
    if (mediumMonthMatch) {
	DEBUG_DATE(@"using medium format: %@", mediumFormat);
	dateFormat = mediumFormat;
    } else {
	OFCreateRegularExpression(longMonthRegex, @"[a-z]{3,}");
	OFRegularExpressionMatch *longMonthMatch = [longMonthRegex of_firstMatchInString:dateString];
	if (longMonthMatch) {
	    DEBUG_DATE(@"using long format: %@", longFormat);
	    dateFormat = longFormat;
	}
    }
    DEBUG_DATE(@"using date format: %@", dateFormat);
    OFCreateRegularExpression(formatseparatorRegex, @"^\\w+([\\./-])");
    OFRegularExpressionMatch *formattedDateMatch = [formatseparatorRegex of_firstMatchInString:dateFormat];
    NSString *formatStringseparator = nil;
    if (formattedDateMatch)
	formatStringseparator = [formattedDateMatch captureGroupAtIndex:0];
    
    
    DatePosition datePosition;
    if ([separator isEqualToString:@"-"] && ![formatStringseparator isEqualToString:@"-"]) { // use (!mediumMonthMatch/longMonthMatch instead of formatStringseparator?
	DEBUG_DATE(@"setting ISO DASH order, formatseparator: %@", formatStringseparator);
	datePosition.year = 1;
	datePosition.month = 2;
	datePosition.day = 3;
	datePosition.separator = @"-";
    } else {
	DEBUG_DATE(@"using DETERMINED, formatseparator: %@", formatStringseparator);
	datePosition= [self _dateElementOrderFromFormat:dateFormat];
    }
    
    // <bug://bugs/39123> 
    NSUInteger count = [dateComponents count];
    if (count == 2) {
	DEBUG_DATE(@"only 2 numbers, one needs to be the day, the other the month, if the month comes before the day, and the month comes before the year, then assign the first number to the month");
	if (datePosition.month >= 2 && datePosition.day == 1) {
	    datePosition.month = 2;
	    datePosition.year = 3;
	} else if (datePosition.month <= 2 && datePosition.day == 3) {
	    datePosition.month = 1;
	    datePosition.day = 2;
	    datePosition.year = 3;
	} 
    }
    
    OBASSERT(datePosition.day != 0);
    OBASSERT(datePosition.month != 0);
    OBASSERT(datePosition.year != 0);
    
    DEBUG_DATE(@"the date positions being used to assign are: day:%ld month:%ld, year:%ld", datePosition.day, datePosition.month, datePosition.year);
    
    DateSet dateSet = [self _dateSetFromArray:dateComponents withPositions:datePosition];
    DEBUG_DATE(@"date components: %@, SETTING TO: day:%ld month:%ld, year:%ld", dateComponents, dateSet.day, dateSet.month, dateSet.year);
    if (dateSet.day == -1 && dateSet.month == -1 && dateSet.year == -1)
	return nil;
        
    // set unset year to next year
    if (dateSet.year == -1) {
	if (dateSet.month < [currentComponents month])
	    dateSet.year = [currentComponents year]+1;
    }
	
    // set the month day and year components if they exist
    if (dateSet.day > 0)
	[currentComponents setDay:dateSet.day];
    else
	[currentComponents setDay:1];
    
    if (dateSet.month > 0)
	[currentComponents setMonth:dateSet.month];
    
    if (dateSet.year > 0)
	[currentComponents setYear:dateSet.year];
    
    DEBUG_DATE(@"year: %ld, month: %ld, day: %ld", [currentComponents year], [currentComponents month], [currentComponents day]);
    date = [calendar dateFromComponents:currentComponents];
    return date;
}

- (DateSet)_dateSetFromArray:(NSArray *)dateComponents withPositions:(DatePosition)datePosition;
{
    DateSet dateSet;
    dateSet.day = -1;
    dateSet.month = -1;
    dateSet.year = -1;
    
    NSUInteger count = [dateComponents count];
    DEBUG_DATE(@"date components: %@, day:%ld month:%ld, year:%ld", dateComponents, datePosition.day, datePosition.month, datePosition.year);
    /**Initial Setting**/
    BOOL didSwap = NO;
    // day
    if (datePosition.day <= count) {
	dateSet.day= [[dateComponents objectAtIndex:datePosition.day-1] intValue];
	if (dateSet.day == 0) {
	    // the only way for zero to get set is for intValue to be unable to return an int, which means its probably a month, swap day and month
	    NSInteger position = datePosition.day;
	    datePosition.day = datePosition.month;
	    datePosition.month = position;
	    dateSet.day= [[dateComponents objectAtIndex:datePosition.day-1] intValue];
	    didSwap = YES;
	}
    }
    
    // year
    BOOL readYear = NO;
    if (datePosition.year <= count) {
	readYear = YES;
	dateSet.year = [[dateComponents objectAtIndex:datePosition.year-1] intValue];
	if (dateSet.year == 0) {
	    NSString *yearString = [[dateComponents objectAtIndex:datePosition.year-1] lowercaseString];
	    if (![yearString hasPrefix:@"0"])
		dateSet.year = -1;
	    if (dateSet.year == -1 && !didSwap) {
		// the only way for zero to get set is for intValue to be unable to return an int, which means its probably a month, swap day and month
		NSInteger position = datePosition.year;
		datePosition.year = datePosition.month;
		datePosition.month = position;
		dateSet.year = [[dateComponents objectAtIndex:datePosition.year-1] intValue];
	    }
	}
    }
    // month
    if (datePosition.month <= count) {
	NSString *monthName = [[dateComponents objectAtIndex:datePosition.month-1] lowercaseString];
	
	NSString *match;
	NSEnumerator *monthEnum = [_months objectEnumerator];
	while ((match = [monthEnum nextObject]) && dateSet.month == -1) {
	    match = [match lowercaseString];
	    if ([match isEqualToString:monthName]) {
		dateSet.month = [self _monthIndexForString:match];
	    }
	}
	NSEnumerator *shortMonthEnum = [_shortmonths objectEnumerator];
	while ((match = [shortMonthEnum nextObject]) && dateSet.month == -1) {
	    match = [match lowercaseString];
	    if ([match isEqualToString:monthName]) {
		dateSet.month = [self _monthIndexForString:match];
	    }
	}
	NSEnumerator *alternateShortmonthEnum = [_alternateShortmonths objectEnumerator];
	while ((match = [alternateShortmonthEnum nextObject]) && dateSet.month == -1) {
	    match = [match lowercaseString];
	    if ([match isEqualToString:monthName]) {
		dateSet.month = [self _monthIndexForString:match];
	    }
	}
	
	if (dateSet.month == -1 )
	    dateSet.month = [monthName intValue];
	else
	    dateSet.month++;	
    }	
    
    /**Sanity Check**/
    int sanity = 2;
    while (sanity--) {
	DEBUG_DATE(@"%d SANITY: day: %ld month: %ld year: %ld", sanity, dateSet.day, dateSet.month, dateSet.year);
	if (count == 1) {
	    if (dateSet.day > 31) {
		DEBUG_DATE(@"single digit is too high for a day, set to year: %ld", dateSet.day);
		dateSet.year = dateSet.day;
		dateSet.day = -1;
	    } else if (dateSet.month > 12 ) {
		DEBUG_DATE(@"single digit is too high for a day, set to month: %ld", dateSet.month);
		dateSet.day = dateSet.month;
		dateSet.month = -1;
	    }
	} else if (count == 2) {
	    if (dateSet.day > 31) {
		DEBUG_DATE(@"swap day and year");
		NSInteger year = dateSet.year;
		dateSet.year = dateSet.day;
		dateSet.day = year;
	    } else if (dateSet.month > 12 ) {
		DEBUG_DATE(@"swap month and year");
		NSInteger year = dateSet.year;
		dateSet.year = dateSet.month;
		dateSet.month = year;
	    } else if (dateSet.day > 0 && dateSet.year > 0 && dateSet.month < 0 ) {
		DEBUG_DATE(@"swap month and day");
		NSInteger day = dateSet.day;
		dateSet.day = dateSet.month;
		dateSet.month = day;
	    }
	}else if (count == 3 ) {
	    DEBUG_DATE(@"sanity checking a 3 compoent date. Day: %ld, Month: %ld Year: %ld", dateSet.day, dateSet.month, dateSet.year);
	    if (dateSet.day > 31) {
		DEBUG_DATE(@"swap day and year");
		NSInteger year = dateSet.year;
		dateSet.year = dateSet.day;
		dateSet.day = year;
	    } else if (dateSet.month > 12 && dateSet.day <= 31 && dateSet.year <= 12) {
		DEBUG_DATE(@"swap month and year");
		NSInteger year = dateSet.year;
		dateSet.year = dateSet.month;
		dateSet.month = year;
	    } else if ( dateSet.day <= 12 && dateSet.month > 12 ) {
		DEBUG_DATE(@"swap day and month");
		NSInteger day = dateSet.day;
		dateSet.day = dateSet.month;
		dateSet.month = day;
	    }
	    DEBUG_DATE(@"after any swaps we're now at: Day: %ld, Month: %ld Year: %ld", dateSet.day, dateSet.month, dateSet.year);
	}
    }
    
    // unacceptable date
    if (dateSet.month > 12 || dateSet.day > 31) {
	DEBUG_DATE(@"Insane Date, month: %ld is greater than 12, or day: %ld is greater than 31", dateSet.month, dateSet.day);
	dateSet.day = -1;
	dateSet.month = -1;
	dateSet.year = -1;    
	return dateSet;
    }
    
    // fiddle with year
    if (readYear) {
	if (dateSet.year >= 90 && dateSet.year <= 99)
	    dateSet.year += 1900;
	else if (dateSet.year < 90)
	    dateSet.year +=2000;
    } 
 
    return dateSet;
}

- (NSDate *)_parseDateNaturalLangauge:(NSString *)dateString withDate:(NSDate *)date timeSpecific:(BOOL *)timeSpecific useEndOfDuration:(BOOL)useEndOfDuration calendar:(NSCalendar *)calendar error:(NSError **)error;
{
    DEBUG_DATE(@"Parse Natural Language Date String (before normalization): \"%@\"", dateString );
    
    dateString = [dateString stringByNormalizingWithOptions:OFRelativeDateParserNormalizeOptionsDefault locale:[self locale]];

    DEBUG_DATE(@"Parse Natural Language Date String (after normalization): \"%@\"", dateString );

    OFRelativeDateParserRelativity modifier = OFRelativeDateParserNoRelativity; // look for a modifier as the first part of the string
    NSDateComponents *currentComponents = [calendar components:unitFlags fromDate:date]; // the given date as components
    
    DEBUG_DATE(@"PRE comps. m: %ld, d: %ld, y: %ld", [currentComponents month], [currentComponents day], [currentComponents year]);
    int multiplier = [self _multiplierForModifer:modifier];
    
    NSInteger month = -1;
    NSInteger weekday = -1;
    NSInteger day = -1;
    NSInteger year = -1;
    NSDateComponents *componentsToAdd = [[[NSDateComponents alloc] init] autorelease];
    
    int number = -1;
    DPCode dpCode = -1;
    dateString = [dateString stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
    NSScanner *scanner = [NSScanner localizedScannerWithString:dateString];
    NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
    [scanner setCaseSensitive:NO];
    BOOL needToProcessNumber = NO;
    BOOL modifierForNumber = NO;
    BOOL daySpecific = NO;
    while (![scanner isAtEnd] || needToProcessNumber) {
	[scanner scanCharactersFromSet:whitespaceCharacterSet intoString:NULL];
	
	BOOL scanned = NO;	
	BOOL isYear = NO;
	BOOL isTickYear = NO;
	if (![scanner isAtEnd]) {
	    
	    // relativeDateNames
	    {
		// use a reverse sorted key array so that abbreviations come last
		NSMutableArray *sortedKeyArray = [relativeDateNames mutableCopyKeys];
                [sortedKeyArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
                [sortedKeyArray reverse];
		for(NSString *name in sortedKeyArray) {
		    NSString *match;
                    NSUInteger savedScanLocation = [scanner scanLocation];
		    if ([scanner scanString:name intoString:&match]) {
                        // This is pretty terrible. We frontload parsing of relative day names, but we shouldn't consume 'dom' (Italian) if the user entered 'Domenica'.
                        // If we are in the middle of a word, don't consume the match.
                        // When we clean up this code (rewrite the parsing loop?) we should probably make it so that we have a flattened list of words and associated quanitites that we parse all at once, preferring longest match.
                        if (![scanner isAtEnd]) {
                            unichar ch = [[scanner string] characterAtIndex:[scanner scanLocation]];
                            if ([[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:ch]) {
                                [scanner setScanLocation:savedScanLocation];
                                continue;
                            }
                        }
                    
                    
			// array info: Code, Number, Relativitity, timeSpecific, monthSpecific, daySpecific
			NSArray *dateOffset = [relativeDateNames objectForKey:match];
			DEBUG_DATE(@"found relative date match: %@", match);
			daySpecific = [[dateOffset objectAtIndex:5] boolValue];
			*timeSpecific = [[dateOffset objectAtIndex:3] boolValue];
			if (!*timeSpecific) {
			    // clear times
			    [currentComponents setHour:0];
			    [currentComponents setMinute:0];
			    [currentComponents setSecond:0];
			}
			
			BOOL monthSpecific = [[dateOffset objectAtIndex:4] boolValue];
			if (!monthSpecific) 
			    [currentComponents setMonth:1];
			 			
			// apply the codes from the dateOffset array
			int codeInt = [[dateOffset objectAtIndex:1] intValue];
			if (codeInt != 0) {
			    int codeString = [[dateOffset objectAtIndex:0] intValue];
			    if (codeString == DPHour)
				*timeSpecific = YES;
			    
			    [self _addToComponents:currentComponents codeString:codeString codeInt:codeInt withMultiplier:[self _multiplierForModifer:[[dateOffset objectAtIndex:2] intValue]]];
			}
		    }
		}
                [sortedKeyArray release];
	    }
	    
	    // specialCaseTimeNames
	    {
		// use a reverse sorted key array so that abbreviations come last
                NSMutableArray *sortedKeyArray = [specialCaseTimeNames mutableCopyKeys];
		[sortedKeyArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
                [sortedKeyArray reverse];
		for(NSString *name in sortedKeyArray) {
		    NSString *match;
		    if ([scanner scanString:name intoString:&match]) {
			DEBUG_DATE(@"found special case match: %@", match);
			daySpecific = YES;
			if (!*timeSpecific) {
			    // clear times
			    [currentComponents setHour:0];
			    [currentComponents setMinute:0];
			    [currentComponents setSecond:0];
			}
			
			NSString *dayName;
			if (useEndOfDuration) 
			    dayName = [_weekdays lastObject];
			else 
			    dayName = [_weekdays objectAtIndex:0];
			
			NSString *start_end_of_next_week = [NSString stringWithFormat:@"+ %@", dayName];
			NSString *start_end_of_last_week = [NSString stringWithFormat:@"- %@", dayName];
			NSString *start_end_of_this_week = [NSString stringWithFormat:@"~ %@", dayName];
			NSDictionary *keywordDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
							   start_end_of_next_week, @"START_END_OF_NEXT_WEEK",
							   start_end_of_last_week, @"START_END_OF_LAST_WEEK",
							   start_end_of_this_week, @"START_END_OF_THIS_WEEK", 
							   nil];
			
			NSString *replacementString = [[specialCaseTimeNames objectForKey:match] stringByReplacingKeysInDictionary:keywordDictionary startingDelimiter:@"$(" endingDelimiter:@")" removeUndefinedKeys:YES]; 
			DEBUG_DATE(@"found: %@, replaced with: %@ from dict: %@", [specialCaseTimeNames objectForKey:match], replacementString, keywordDictionary);
			date = [self _parseDateNaturalLangauge:replacementString withDate:date timeSpecific:timeSpecific useEndOfDuration:useEndOfDuration calendar:calendar error:error];
			currentComponents = [calendar components:unitFlags fromDate:date]; // update the components
			DEBUG_DATE(@"RETURN from replacement call");
		    }
		}
		[sortedKeyArray release];
	    }
	   	    
	    NSString *name;
	    // check for any modifier after we check the relative date names, as the relative date names can be phrases that we want to match with
	    NSEnumerator *patternEnum = [modifiers keyEnumerator];
	    NSString *pattern;
	    while ((pattern = [patternEnum nextObject])) {
		NSString *match;
		if ([scanner scanString:pattern intoString:&match]) {
		    modifier = [[modifiers objectForKey:pattern] intValue];
		    DEBUG_DATE(@"Found Modifier: %@", match);
		    multiplier = [self _multiplierForModifer:modifier];
		    modifierForNumber = YES;
		}
	    } 
	    
	    // test for month names
            if (month == -1) {
                NSArray *monthArrays = [NSArray arrayWithObjects:_months, _shortmonths, _alternateShortmonths, nil];
                NSUInteger i, numberOfMonthArrays = [monthArrays count];
                
                for (i = 0; i < numberOfMonthArrays; i++) {
                    NSEnumerator *monthEnum = [[monthArrays objectAtIndex:i] objectEnumerator];
                    while ((name = [monthEnum nextObject])) {
                        NSString *match;
                        NSUInteger savedScanLocation = [scanner scanLocation];
                        if ([scanner scanString:name intoString:&match]) {

                            // don't consume a partial match
                            if (![scanner isAtEnd]) {
                                unichar ch = [[scanner string] characterAtIndex:[scanner scanLocation]];
                                if ([[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:ch]) {
                                    [scanner setScanLocation:savedScanLocation];
                                    continue;
                                }
                            }

                            month = [self _monthIndexForString:match];
                            scanned = YES;
                            DEBUG_DATE(@"matched name: %@ to match: %@", name, match);
                            break;
                        }
                    }

                    if (month != -1)
                        break;
                }            
            }

	    //look for a year '
	    if ([scanner scanString:@"'" intoString:NULL]) {
		isYear = YES;
		isTickYear = YES;
		scanned = YES;
	    } 
	    [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	}
	
	if (number != -1) {
	    needToProcessNumber = NO;
	    BOOL foundCode = NO;
	    NSString *codeString;
            NSMutableArray *sortedKeyArray = [codes mutableCopyKeys];
	    [sortedKeyArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
	    NSEnumerator *codeEnum = [sortedKeyArray reverseObjectEnumerator];
	    while ((codeString = [codeEnum nextObject]) && !foundCode && (![scanner isAtEnd])) {
		if ([scanner scanString:codeString intoString:NULL]) {
		    dpCode = [[codes objectForKey:codeString] intValue];
		    if (number != 0) // if we aren't going to add anything don't call
			[self _addToComponents:componentsToAdd codeString:dpCode codeInt:number withMultiplier:multiplier];
		    DEBUG_DATE( @"codeString:%@, number:%d, mult:%d", codeString, number, multiplier );
		    daySpecific = YES;
		    isYear = NO; // '97d gets you 97 days
		    foundCode= YES;
		    scanned = YES;
		    modifierForNumber = NO;
		    number = -1;  
		}
	    }
            [sortedKeyArray release];
	    
	    if (isYear) {
		year = number;
		number = -1;  
	    } else if (!foundCode) {
		if (modifierForNumber) {
		    // we had a modifier with no code attached, assume day
		    if (day == -1) {
			if (number < 31 )
			    day = number;
			else
			    year = number;
		    } else {
			year = number;
		    }
		    modifierForNumber = NO;
		    daySpecific = YES;
		    DEBUG_DATE(@"free number, marking added to day as true");
		} else if (number > 31 || day != -1) {
		    year = number;
		    if (year > 90 && year < 100)
			year += 1900;
		    else if (year < 90)
			year +=2000;
		} else {
		    day = number;
		    daySpecific = YES;
		}
		number = -1;  
	    } else if (isTickYear) {
		if (year > 90)
		    year += 1900;
		else 
		    year +=2000;
	    }
	}

        // scan weekday names
        if (weekday == -1) {
            for (NSString *name in _weekdays) {
                NSString *match;
                if ([scanner scanString:name intoString:&match]) {
                    weekday = [self _weekdayIndexForString:match];
                    daySpecific = YES;
                    scanned = YES;
                    DEBUG_DATE(@"matched name: %@ to match: %@ weekday: %ld", name, match, weekday);
                }
            }
        }
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];

	// scan short weekdays after codes to allow for months to be read instead of mon
	if (weekday == -1) {
            for (NSString *name in _shortdays) {
		NSString *match;
		if ([scanner scanString:name intoString:&match]) {
		    weekday = [self _weekdayIndexForString:match];
		    daySpecific = YES;
		    scanned = YES;
		    DEBUG_DATE(@"matched name: %@ to match: %@", name, match);
		}
	    }
	}
	[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
        
        // scan the alternate short weekdays (stripped of punctuation)
	if (weekday == -1) {
            for (NSString *name in _alternateShortdays) {
		NSString *match;
		if ([scanner scanString:name intoString:&match]) {
		    weekday = [self _weekdayIndexForString:match];
		    daySpecific = YES;
		    scanned = YES;
		    DEBUG_DATE(@"matched name: %@ to match: %@", name, match);
		}
	    }
	}
	[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];

        // scan short month names after scanning full weekday names
        if (month == -1) {
            for (NSString *name in _shortmonths) {
                NSString *match;
                if ([scanner scanString:name intoString:&match]) {
                    month = [self _monthIndexForString:match];
                    scanned = YES;
                    DEBUG_DATE(@"matched name: %@ to match: %@", name, match);
                }
            }
        }
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];

        // scan the alternate short month names (stripped of punctuation)
        if (month == -1) {
            for (NSString *name in _alternateShortmonths) {
                NSString *match;
                if ([scanner scanString:name intoString:&match]) {
                    month = [self _monthIndexForString:match];
                    scanned = YES;
                    DEBUG_DATE(@"matched name: %@ to match: %@", name, match);
                }
            }
        }
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	// scan english short weekdays after codes to allow for months to be read instead of mon
	if (weekday == -1) {
	    NSEnumerator *shortdaysEnum = [englishShortdays objectEnumerator];
	    NSString *name;
	    while ((name = [shortdaysEnum nextObject])) {
		NSString *match;
		if ([scanner scanString:name intoString:&match]) {
		    weekday = [self _weekdayIndexForString:match];
		    daySpecific = YES;
		    scanned = YES;
		    DEBUG_DATE(@"ENGLISH matched name: %@ to match: %@", name, match);
		}
	    }
	}
	[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	
	if (weekday != -1) {
	    date = [self _modifyDate:date withWeekday:weekday withModifier:modifier calendar:calendar];
	    currentComponents = [calendar components:unitFlags fromDate:date];
	    weekday = -1;
	    modifier = 0;
	    multiplier = [self _multiplierForModifer:modifier];
	}
	
	//check for any modifier again, before checking for numbers, so that we can record the proper modifier
	NSEnumerator *patternEnum = [modifiers keyEnumerator];
	NSString *pattern;
	while ((pattern = [patternEnum nextObject])) {
	    NSString *match;
	    if ([scanner scanString:pattern intoString:&match]) {
		modifier = [[modifiers objectForKey:pattern] intValue];
		multiplier = [self _multiplierForModifer:modifier];
		modifierForNumber = YES;
	    }
	} 
	
	// look for a number
	if ([scanner scanInt:&number]) {
	    needToProcessNumber = YES;
	    scanned = YES;
	}
	[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	
	// eat any punctuation
	BOOL punctuation = NO;
	if ([scanner scanCharactersFromSet:[NSCharacterSet punctuationCharacterSet] intoString:NULL]) {
	    DEBUG_DATE(@"scanned some symbols");
	    punctuation = YES;
	}
	
	if ([scanner scanLocation] == [[scanner string] length] && !needToProcessNumber) {
	    break;
	} else {
	    if (!scanned) {
		[scanner setScanLocation:[scanner scanLocation]+1];
	    }
	}
	DEBUG_DATE(@"end of scanning cycle. month: %ld, day: %ld, year: %ld, weekday: %ld, number: %d, modifier: %d", month, day, year, weekday, number, multiplier);
	//OBError(&*error, // error
	//		0,  // code enum
	//		@"we were unable to parse something, return an error for string" // description
	//		);
	if (number == -1 && !scanned) {
	    if (!punctuation) {
		DEBUG_DATE(@"ERROR String: %@, number: %d loc: %ld", dateString, number, [scanner scanLocation]);
		return nil;
	    }
	}
	
    } // scanner
    
    if (!daySpecific) {
	if (useEndOfDuration) {
	    // find the last day of the month of the components ?
	}
	day = 1;
	DEBUG_DATE(@"setting the day to 1 as a default");
    }
    if (day != -1) {
	[currentComponents setDay:day];
    }
    
    // TODO: default month?
    if (month != -1) {
	if (useEndOfDuration) {
	    // find the last month of the year ?
	}
	month+=1;
	[currentComponents setYear:[self _determineYearForMonth:month withModifier:modifier fromCurrentMonth:[currentComponents month] fromGivenYear:[currentComponents year]]];
	[currentComponents setMonth:month];
    }
    
    // TODO: default year?
    if (year != -1) 
	[currentComponents setYear:year];
    
    date = [calendar dateFromComponents:currentComponents];
    DEBUG_DATE(@"comps. m: %ld, d: %ld, y: %ld", [currentComponents month], [currentComponents day], [currentComponents year]);
    DEBUG_DATE(@"date before modifying with the components: %@", date) ;

    // componetsToAdd is all of the collected relative date codes
    date = [calendar dateByAddingComponents:componentsToAdd toDate:date options:0];
    return date;
}

- (int)_multiplierForModifer:(int)modifier;
{
    if (modifier == OFRelativeDateParserPastRelativity)
	return -1;
    return 1;
}

- (NSUInteger)_monthIndexForString:(NSString *)token;
{
    // return the the value of the month according to its position on the array, or -1 if nothing matches.
    NSUInteger monthIndex = [_months count];
    while (monthIndex--) {
	if ([token isEqualToString:[_shortmonths objectAtIndex:monthIndex]] || [token isEqualToString:[_alternateShortmonths objectAtIndex:monthIndex]] || [token isEqualToString:[_months objectAtIndex:monthIndex]]) {
	    return monthIndex;
	}
    }
    return -1;
}

- (NSUInteger)_weekdayIndexForString:(NSString *)token;
{
    // return the the value of the weekday according to its position on the array, or -1 if nothing matches.
    
    NSUInteger dayIndex = [_weekdays count];
    token = [token lowercaseString];
    while (dayIndex--) {
        DEBUG_DATE(@"token: %@, weekdays: %@, short: %@, Ewdays: %@, EShort: %@", token, [[_weekdays objectAtIndex:dayIndex] lowercaseString], [[_shortdays objectAtIndex:dayIndex] lowercaseString], [[englishWeekdays objectAtIndex:dayIndex] lowercaseString], [[englishShortdays objectAtIndex:dayIndex] lowercaseString]);
	if ([token isEqualToString:[_alternateShortdays objectAtIndex:dayIndex]] ||
            [token isEqualToString:[_shortdays objectAtIndex:dayIndex]] ||
            [token isEqualToString:[_weekdays objectAtIndex:dayIndex]]) {
	    return dayIndex;
        }
	
	// test the english weekdays
	if ([token isEqualToString:[englishShortdays objectAtIndex:dayIndex]] || [token isEqualToString:[englishWeekdays objectAtIndex:dayIndex]])
            return dayIndex;
    }

    DEBUG_DATE(@"weekday index not found for: %@", token);
    
    return -1;
}

- (NSInteger)_determineYearForMonth:(NSUInteger)month withModifier:(OFRelativeDateParserRelativity)modifier fromCurrentMonth:(NSUInteger)currentMonth fromGivenYear:(NSInteger)givenYear;
{
    // current month equals the requested month
    if (currentMonth == month) {
	switch (modifier) {
	    case OFRelativeDateParserFutureRelativity:
		return (givenYear+1);
	    case OFRelativeDateParserPastRelativity:
		return (givenYear-1);
	    default:
		return givenYear;
	} 
    } else if (currentMonth > month) {
	if ( modifier != OFRelativeDateParserPastRelativity ) {
	    return (givenYear +1);
	} 
    } else {
	if (modifier == OFRelativeDateParserPastRelativity) {
	    return (givenYear-1);
	}
    }
    return givenYear;
}

- (NSDate *)_modifyDate:(NSDate *)date withWeekday:(NSUInteger)requestedWeekday withModifier:(OFRelativeDateParserRelativity)modifier calendar:(NSCalendar *)calendar;
{
    OBPRECONDITION(date);
    OBPRECONDITION(calendar);
    
    requestedWeekday+=1; // add one to the index since weekdays are 1 based, but we detect them zero-based
    NSDateComponents *weekdayComp = [calendar components:NSWeekdayCalendarUnit fromDate:date];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    NSUInteger currentWeekday = [weekdayComp weekday];
    
    DEBUG_DATE(@"Modifying the date based on weekdays with modifer: %d, Current Weekday: %ld, Requested Weekday: %ld", modifier, currentWeekday, requestedWeekday);
    
    // if there is no modifier then we just take the current day if its a match, or the next instance of the requested day
    if (modifier == OFRelativeDateParserNoRelativity) {
	DEBUG_DATE(@"NO Modifier");
	if (currentWeekday == requestedWeekday) {
	    DEBUG_DATE(@"return today");
            [components release];
	    return date; 
	} else if (currentWeekday > requestedWeekday) {
	    DEBUG_DATE( @"set the weekday to the next instance of the requested day, %ld days in the future", (7-(currentWeekday - requestedWeekday)));
	    [components setDay:(7-(currentWeekday - requestedWeekday))];
	} else if (currentWeekday < requestedWeekday) {
	    DEBUG_DATE( @"set the weekday to the next instance of the requested day, %ld days in the future", (requestedWeekday- currentWeekday) );
	    [components setDay:(requestedWeekday- currentWeekday)];
	}
    } else {
	
	// if there is a modifier, add a week if its "next", sub a week if its "last", or stay in the current week if its "this"
	int dayModification = 0;
	switch(modifier) {    
	    case OFRelativeDateParserNoRelativity:
	    case OFRelativeDateParserCurrentRelativity:
		break;
	    case OFRelativeDateParserFutureRelativity: // "next"
		dayModification = 7;
		DEBUG_DATE(@"CURRENT Modifier \"this\"");
		break;
	    case OFRelativeDateParserPastRelativity: // "last"
		dayModification = -7;
		DEBUG_DATE(@"PAST Modifier \"last\"");
		break;
	}
	
	DEBUG_DATE( @"set the weekday to: %ld days difference from the current weekday: %ld, BUT add %d days", (requestedWeekday- currentWeekday), currentWeekday, dayModification );
	[components setDay:(requestedWeekday- currentWeekday)+dayModification];
    }
    
    NSDate *result = [calendar dateByAddingComponents:components toDate:date options:0];; //return next week
    [components release];
    return result;
}

- (void)_addToComponents:(NSDateComponents *)components codeString:(DPCode)dpCode codeInt:(int)codeInt withMultiplier:(int)multiplier;
{
    codeInt*=multiplier;
    switch (dpCode) {
	case DPHour:
	    if ([components hour] == NSUndefinedDateComponent)
		[components setHour:codeInt];
	    else
		[components setHour:[components hour] + codeInt];
	    DEBUG_DATE( @"Added %d hours to the components, now at: %ld hours", codeInt, [components hour] );
	    break;
	    case DPDay:
	    if ([components day] == NSUndefinedDateComponent)
		[components setDay:codeInt];
	    else 
		[components setDay:[components day] + codeInt];
	    DEBUG_DATE( @"Added %d days to the components, now at: %ld days", codeInt, [components day] );
	    break;
	    case DPWeek:
	    if ([components day] == NSUndefinedDateComponent)
		[components setDay:codeInt*7];
	    else
		[components setDay:[components day] + codeInt*7];
	    DEBUG_DATE( @"Added %d weeks(ie. days) to the components, now at: %ld days", codeInt, [components day] );
	    break;
	    case DPMonth:
	    if ([components month] == NSUndefinedDateComponent)
		[components setMonth:codeInt];
	    else 
		[components setMonth:[components month] + codeInt];
	    DEBUG_DATE( @"Added %d months to the components, now at: %ld months", codeInt, [components month] );
	    break;
	    case DPYear:
	    if ([components year] == NSUndefinedDateComponent)
		[components setYear:codeInt];
	    else 
		[components setYear:[components year] + codeInt];
	    DEBUG_DATE( @"Added %d years to the components, now at: %ld years", codeInt, [components year] );
	    break;
    }
}

+ (NSDictionary *)_dictionaryByNormalizingKeysInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options locale:(NSLocale *)locale;
{
    OBPRECONDITION(dictionary);
    
    NSMutableDictionary *normalizedDictionary = [NSMutableDictionary dictionary];
    NSEnumerator *keyEnumerator = [dictionary keyEnumerator];
    NSString *key = nil;
    
    while (nil != (key = [keyEnumerator nextObject])) {
        NSString *newKey = [key stringByNormalizingWithOptions:options locale:locale];
        NSString *value = [dictionary objectForKey:key];
        [normalizedDictionary setObject:value forKey:newKey];
    }

    return [[normalizedDictionary copy] autorelease];
}

+ (NSDictionary *)_dictionaryByNormalizingValuesInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options locale:(NSLocale *)locale;
{
    OBPRECONDITION(dictionary);
    
    NSMutableDictionary *normalizedDictionary = [NSMutableDictionary dictionary];
    NSEnumerator *keyEnumerator = [dictionary keyEnumerator];
    NSString *key = nil;
    
    while (nil != (key = [keyEnumerator nextObject])) {
        NSString *value = [[dictionary objectForKey:key] stringByNormalizingWithOptions:options locale:locale];
        [normalizedDictionary setObject:value forKey:key];
    }

    return [[normalizedDictionary copy] autorelease];
}

+ (NSArray *)_arrayByNormalizingValuesInArray:(NSArray *)array options:(NSUInteger)options locale:(NSLocale *)locale;
{
    OBPRECONDITION(array);
    
    NSMutableArray *normalizedArray = [NSMutableArray array];
    
    NSUInteger i, count = [array count];
    for (i = 0; i < count; i++) {
        NSString *string = [[array objectAtIndex:i] stringByNormalizingWithOptions:options locale:locale];
        [normalizedArray addObject:string];
    }
    
    return [[normalizedArray mutableCopy] autorelease];
}

- (NSDictionary *)_dictionaryByNormalizingKeysInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options;
{
    return [[self class] _dictionaryByNormalizingKeysInDictionary:dictionary options:options locale:[self locale]];
}

- (NSDictionary *)_dictionaryByNormalizingValuesInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options;
{
    return [[self class] _dictionaryByNormalizingValuesInDictionary:dictionary options:options locale:[self locale]];
}

- (NSArray *)_arrayByNormalizingValuesInArray:(NSArray *)array options:(NSUInteger)options;
{
    return [[self class] _arrayByNormalizingValuesInArray:array options:options locale:[self locale]];
}

@end

@implementation OFRelativeDateParser (OFInternalAPI)

- (DatePosition)_dateElementOrderFromFormat:(NSString *)dateFormat;
{
    OBASSERT(dateFormat);
    
    DatePosition datePosition;
    datePosition.day = 1;
    datePosition.month = 2;
    datePosition.year = 3;
    datePosition.separator = @" ";
    
    OFCreateRegularExpression(mdyRegex, @"[mM]+(\\s?)(\\S?)(\\s?)d+(\\s?)(\\S?)(\\s?)y+");
    OFRegularExpressionMatch *match = [mdyRegex of_firstMatchInString:dateFormat];
    if (match) {
	datePosition.day = 2;
	datePosition.month = 1;
	datePosition.year = 3;
	datePosition.separator = [match captureGroupAtIndex:0];
	return datePosition;
    }
    
    OFCreateRegularExpression(dmyRegex, @"d+(\\s?)(\\S?)(\\s?)[mM]+(\\s?)(\\S?)(\\s?)y+");
    match = [dmyRegex of_firstMatchInString:dateFormat];
    if (match) {
	datePosition.day = 1;
	datePosition.month = 2;
	datePosition.year = 3;
	datePosition.separator = [match captureGroupAtIndex:0];
	return datePosition;
    }
    
    OFCreateRegularExpression(ymdRegex, @"y+(\\s?)(\\S?)(\\s?)[mM]+(\\s?)(\\S?)(\\s?)d+");
    match = [ymdRegex of_firstMatchInString:dateFormat];
    if (match) {
	datePosition.day = 3;
	datePosition.month = 2;
	datePosition.year = 1;
	datePosition.separator = [match captureGroupAtIndex:0];
	return datePosition;
    }
    
    OFCreateRegularExpression(ydmRegex, @"y+(\\s?)(\\S?)(\\s?)d+(\\s?)(\\S?)(\\s?)[mM]+");
    match = [ydmRegex of_firstMatchInString:dateFormat];
    if (match) {
	datePosition.day = 2;
	datePosition.month = 3;
	datePosition.year = 1;
	datePosition.separator = [match captureGroupAtIndex:0];
	return datePosition;
    }
    
    // log inavlid dates and use the american default, for now
    
    {
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        OBASSERT([formatter formatterBehavior] == NSDateFormatterBehavior10_4);
        
	[formatter setDateStyle:NSDateFormatterShortStyle]; 
	[formatter setTimeStyle:NSDateFormatterNoStyle]; 
	NSString *shortFormat = [[[formatter dateFormat] copy] autorelease];
        
	[formatter setDateStyle:NSDateFormatterMediumStyle]; 
	NSString *mediumFormat = [[[formatter dateFormat] copy] autorelease];
        
	[formatter setDateStyle:NSDateFormatterLongStyle]; 
	NSString *longFormat = [[[formatter dateFormat] copy] autorelease];
        
	NSLog(@"**PLEASE REPORT THIS LINE TO: support@omnigroup.com | Unparseable Custom Date Format. Date Format trying to parse is: %@; Short Format: %@; Medium Format: %@; Long Format: %@", dateFormat, shortFormat, mediumFormat, longFormat);
    }
    return datePosition;
}

@end

