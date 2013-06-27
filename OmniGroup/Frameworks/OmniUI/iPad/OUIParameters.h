// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniQuartz/OQColor.h>

// OUIInspectorWell
#define kOUIInspectorWellHeight (46) // This makes our inner content height match that of a UITableViewCell.
#define kOUIInspectorWellLightBorderGradientStartColor ((OSHSV){213.0/360.0, 0.06, 0.62, 1.0})
#define kOUIInspectorWellLightBorderGradientEndColor ((OSHSV){216.0/360.0, 0.05, 0.72, 1.0})
#define kOUIInspectorWellDarkBorderGradientStartColor ((OSHSV){213.0/360.0, 0.06, 0.20, 1.0})
#define kOUIInspectorWellDarkBorderGradientEndColor ((OSHSV){216.0/360.0, 0.05, 0.35, 1.0})
#define kOUIInspectorWellInnerShadowColor ((OQWhiteAlpha){0.0, 0.35})
#define kOUIInspectorWellInnerShadowBlur (2)
#define kOUIInspectorWellInnerShadowOffset (CGSizeMake(0,1))
#define kOUIInspectorWellOuterShadowColor ((OQWhiteAlpha){1.0, 0.5})
#define kOUIInspectorWellCornerCornerRadiusSmall (4)
#define kOUIInspectorWellCornerCornerRadiusLarge (10.5)

// OUIInspectorTextWell
#define kOUIInspectorTextWellNormalGradientTopColor ((OSHSV){210.0/360.0, 0.08, 1.00, 1.0})
#define kOUIInspectorTextWellNormalGradientBottomColor ((OSHSV){210.0/360.0, 0.02, 1.00, 1.0})
#define kOUIInspectorTextWellHighlightedGradientTopColor ((OSHSV){210.0/360.0, 0.4, 1.0, 1.0})
#define kOUIInspectorTextWellHighlightedGradientBottomColor ((OSHSV){210.0/360.0, 0.2, 1.0, 1.0})
#define kOUIInspectorTextWellButtonHighlightedGradientTopColor ((OSHSV){209.0/360.0, 0.91, 0.96, 1.0})      // matches UITableViewCellSelectionStyleBlue
#define kOUIInspectorTextWellButtonHighlightedGradientBottomColor ((OSHSV){218.0/360.0, 0.93, 0.90, 1.0})   // matches UITableViewCellSelectionStyleBlue

#define kOUIInspectorTextWellTextColor ((OSHSV){221.0/360.0, 0.30, 0.42, 1.0})
#define kOUIInspectorTextWellHighlightedTextColor ((OSHSV){213.0/360.0, 0.50, 0.30, 1.0})
#define kOUIInspectorTextWellHighlightedButtonTextColor ((OQWhiteAlpha){1.0, 1.0})
#define kOUIInspectorLabelDisabledTextColorAlphaScale (0.5)

// OUIInspectorBackgroundView
#define kOUIInspectorBackgroundTopColor ((OQLinearRGBA){228.0/255.0, 231.0/255.0, 235.0/255.0, 1.0})
#define kOUIInspectorBackgroundBottomColor ((OQLinearRGBA){197.0/255.0, 200.0/255.0, 207.0/255.0, 1.0})

// OUIInspectorOptionWheel
#define kOUIInspectorOptionWheelEdgeGradientGray (0.53)
#define kOUIInspectorOptionWheelMiddleGradientGray (1.0)
#define kOUIInspectorOptionWheelGradientPower (2.5)

// OUIDrawing
#define kOUILightContentOnDarkBackgroundShadowColor ((OQWhiteAlpha){0.0, 0.5})
#define kOUIDarkContentOnLightBackgroundShadowColor ((OQWhiteAlpha){1.0, 0.5})

// OUIInspector
#define kOUIInspectorLabelTextColor ((OSHSV){212.0/360.0, 0.5, 0.35, 1.0}) // Also toggle buttons and segmented control buttons if they have labels instead of images
#define kOUIInspectorValueTextColor ((OSHSV){212.0/360.0, 0.5, 0.35, 1.0}) // For lable+value inspectors in detail/tappable mode (which looks like a UITableView now).

// OUIBarButtonItem
#define kOUIBarButtonItemDisabledTextGrayForColoredButtons (0.9) // The default is too dark against these lighter colored buttons (but OK on the black buttons).

// OUIGradientView
#define kOUIShadowEdgeThickness (6.0f)
#define kOUIShadowEdgeMaximumAlpha (0.4f)

// UIScrollView(OUIExtensions)
#define kOUIAutoscrollBorderWidth (44.0 * 1.1) // Area on edge of the screen that defines the ramp for autoscroll speed. Want to be able to hit the max speed without finger risking going off edge of view
#define kOUIAutoscrollMaximumVelocity (850) // in pixels per second
#define kOUIAutoscrollVelocityRampPower (0.25) // power ramp for autoscroll velocity
