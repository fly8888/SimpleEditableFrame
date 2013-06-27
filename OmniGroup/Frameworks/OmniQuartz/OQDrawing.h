// Copyright 2003-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#if TARGET_OS_IPHONE
    #import <UIKit/UIKit.h>
#endif

#import <OmniBase/assertions.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern void OQSetPatternColorReferencePoint(CGPoint point, NSView *view);
#else
#import <CoreGraphics/CoreGraphics.h>
#endif

// 
// Rounded rect support.
// 

typedef enum {
    OQRoundedRectCornerNone,
    OQRoundedRectCornerTopLeft = 0x1,
    OQRoundedRectCornerTopRight = 0x2,
    OQRoundedRectCornerBottomRight = 0x4,
    OQRoundedRectCornerBottomLeft = 0x8,
} OQRoundedRectCorner;

#define OQRectMinXEdge            0x010
#define OQRectMinYEdge            0x020
#define OQRectMaxXEdge            0x040
#define OQRectMaxYEdge            0x080
#define OQRectAllEdges            0x0F0
#define _OQRectAllEdgesShift      4
#define OQRectMinXMinYCorner      0x001
#define OQRectMaxXMinYCorner      0x002
#define OQRectMaxXMaxYCorner      0x004
#define OQRectMinXMaxYCorner      0x008
#define OQRectAllCorners          0x00F

// These do not depend on the flippedness of the coordinate system because they are symmetrical
extern void OQAppendRoundedRect(CGContextRef ctx, CGRect rect, CGFloat radius);
extern void OQAddRoundedRect(CGMutablePathRef path, CGRect rect, CGFloat radius);

// These use the OQRect{Min,Max}{X,Y} flags, and therefore don't depend on the flippedness of the coordinate system
extern void OQAppendRectWithMask(CFTypeRef ctxOrPath, CGRect rect, unsigned int edgeMask);

/*
 Workhorse rounded-rect-with-missing-sides function.
 This doesn't do anything special for the case where the radius is too large; none of its callers currently depend on its behavior in that case. If you need a specific behavior, add it.
*/
extern void OQAppendRoundedRectWithMask_c(CFTypeRef ctxOrPath, CGRect rect, CGFloat radius, unsigned int cornerMask);
static inline void OQAppendRoundedRectWithMask(CFTypeRef ctxOrPath, CGRect rect, CGFloat radius, unsigned int cornerMask)
{
    if ((cornerMask & OQRectAllCorners) == 0)
        OQAppendRectWithMask(ctxOrPath, rect, cornerMask);
    else
        OQAppendRoundedRectWithMask_c(ctxOrPath, rect, radius, cornerMask);
}

// This function assumes a flipped coordinate system (top == CGRectGetMinY, bottom == CGRectGetMaxY)
extern void OQAppendRectWithRoundedCornerMask(CGContextRef ctx, CGRect rect, CGFloat radius, NSUInteger cornerMask);

// These assume a non-flipped coordinate system (top == CGRectGetMaxY, bottom == CGRectGetMinY)
static inline void OQAppendRectWithRoundedTop(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeBottom)
    { OQAppendRoundedRectWithMask_c(ctx, rect, radius, OQRectMaxXMaxYCorner|OQRectMinXMaxYCorner|
                                    (closeBottom?OQRectAllEdges:(OQRectMinXEdge|OQRectMaxXEdge|OQRectMaxYEdge))); }
static inline void OQAppendRectWithRoundedTopRight(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeBottom)
    { OQAppendRoundedRectWithMask_c(ctx, rect, radius, OQRectMaxXMaxYCorner|
                                    (closeBottom?OQRectAllEdges:(OQRectMinXEdge|OQRectMaxXEdge|OQRectMaxYEdge))); }
static inline void OQAppendRectWithRoundedTopLeft(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeBottom)
    { OQAppendRoundedRectWithMask_c(ctx, rect, radius, OQRectMinXMaxYCorner|
                                    (closeBottom?OQRectAllEdges:(OQRectMinXEdge|OQRectMaxXEdge|OQRectMaxYEdge))); }

static inline void OQAppendRectWithRoundedBottom(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeTop)
    { OQAppendRoundedRectWithMask_c(ctx, rect, radius, OQRectMaxXMinYCorner|OQRectMinXMinYCorner|
                                    (closeTop?OQRectAllEdges:(OQRectMinXEdge|OQRectMaxXEdge|OQRectMinYEdge))); }
static inline void OQAppendRectWithRoundedBottomLeft(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeTop)
    { OQAppendRoundedRectWithMask_c(ctx, rect, radius, OQRectMaxXMinYCorner|OQRectMinXMinYCorner|
                                    (closeTop?OQRectAllEdges:(OQRectMinXEdge|OQRectMaxXEdge|OQRectMinYEdge))); }
static inline void OQAppendRectWithRoundedBottomRight(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeTop)
    { OQAppendRoundedRectWithMask_c(ctx, rect, radius, OQRectMaxXMinYCorner|OQRectMinXMinYCorner|
                                    (closeTop?OQRectAllEdges:(OQRectMinXEdge|OQRectMaxXEdge|OQRectMinYEdge))); }

static inline void OQAppendRectWithRoundedLeft(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeRight)
    { OQAppendRoundedRectWithMask_c(ctx, rect, radius, OQRectMinXMinYCorner|OQRectMinXMaxYCorner|
                                    (closeRight?OQRectAllEdges:(OQRectMinXEdge|OQRectMinYEdge|OQRectMaxYEdge))); }
static inline void OQAppendRectWithRoundedRight(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeLeft)
    { OQAppendRoundedRectWithMask_c(ctx, rect, radius, OQRectMaxXMinYCorner|OQRectMaxXMaxYCorner|
                                    (closeLeft?OQRectAllEdges:(OQRectMaxXEdge|OQRectMinYEdge|OQRectMaxYEdge))); }

// Updates the CTM so that the lower/upper edges of the rect are swapped.
static inline void OQFlipVerticallyInRect(CGContextRef ctx, CGRect rect)
{
    CGContextConcatCTM(ctx, (CGAffineTransform){ 1, 0, 0, -1, 0, 2 * rect.origin.y + rect.size.height });
}

extern CGRect OQCenteredIntegralRectInRect(CGRect enclosingRect, CGSize toCenter);
extern CGRect OQLargestCenteredIntegralRectInRectWithAspectRatioAsSize(CGRect enclosingRect, CGSize toCenter);
extern CGRect OQCenterAndFitIntegralRectInRectWithSameAspectRatioAsSize(CGRect enclosingRect, CGSize toCenter);

#if TARGET_OS_IPHONE
extern void OQDrawImageCenteredInRect(CGContextRef ctx, UIImage *image, CGRect rect);
#endif
extern void OQDrawCGImageWithScaleCenteredInRect(CGContextRef ctx, CGImageRef image, CGFloat scale, CGRect rect);

extern void OQPreflightImage(CGImageRef image);
extern CGImageRef OQCopyFlattenedImage(CGImageRef image) CF_RETURNS_RETAINED;
extern CGImageRef OQCreateImageWithSize(CGImageRef image, CGSize size, CGInterpolationQuality interpolationQuality) CF_RETURNS_RETAINED;

void OQCrosshatchRect(CGContextRef ctxt, CGRect rect, CGFloat lineWidth, CGFloat dx, CGFloat dy);


// Returns the overall dilation of a transformation matrix (may be negative if there's a reflection involved)
// This is the proportional change in area of a figure (rectangle, filled path, etc)
static inline CGFloat OQAffineTransformGetDilation(CGAffineTransform m)
{
    return m.a * m.d - m.b * m.c;
}

// SVG-style paths
CGPathRef OQCGPathCreateFromSVGPath(const unsigned char *d, size_t d_length);
int OQCGContextAddSVGPath(CGContextRef cgContext, const unsigned char *d, size_t d_length);

// SVG-style arcs
struct OQEllipseParameters {
    CGPoint center;              // Computed center of the ellipse.
    unsigned int numSegments;    // At most 4 Bezier segments in the result.
    CGPoint points[ 3 * 4 ];     // Three control points per segment; first segment's currentpoint is (0,0).
};
/*
 Computes the parameters of an elliptical arc as given by the SVG-style arc operator.
 delta is the vector from the start to the end of the arc.
 rMaj and rMin are the major and minor radii of the ellipse.
 theta is the angle of the major radius (0 -> towards positive X, pi/4 -> towards +X,+Y).
 largeSweep and posAngle disambiguate between the four possible fits to the above parameters.
 */
void OQComputeEllipseParameters(CGFloat deltaX, CGFloat deltaY,
                                CGFloat rMaj, CGFloat rMin, CGFloat theta,
                                BOOL largeSweep, BOOL posAngle,
                                struct OQEllipseParameters *result);
