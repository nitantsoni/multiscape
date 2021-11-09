//
//  MSBackgroundWorker.m
//  MultiScape
//
//  Created by David Zwerdling on 11/11/10.
//  Copyright 2010 Laughing Man Software. All rights reserved.
//
//
//MultiScape is free software: you can redistribute it and/or modify
//it under the terms of the GNU General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.

//MultiScape is distributed in the hope that it will be useful,
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU General Public License for more details.

//You should have received a copy of the GNU General Public License
//along with MultiScape.  If not, see <http://www.gnu.org/licenses/>.

#import "MSBackgroundWorker.h"

#ifndef REVERSED
    #define REVERSED
#endif

const uint32_t maxDisplays = 20;

@interface MSBackgroundWorker () {
    uint32_t _displayCount;
    CGSize *_allScreenSizes;
    CGSize _perfectSize;
}

- (void)mainThreadCompletionNotification;

@end

@implementation MSBackgroundWorker

@synthesize baseImage;
@synthesize procText;

- (instancetype)init {
    if (self = [super init]) {
        fileManager = [NSFileManager defaultManager];
        sysEventsBridgeApp = [SBApplication applicationWithBundleIdentifier:@"com.apple.SystemEvents"];        
    }    
    return self;
}

- (CGSize)perfectSize {
    CGDirectDisplayID onlineDisplays[maxDisplays];
    _displayCount = 0;
    if (CGGetOnlineDisplayList(maxDisplays, onlineDisplays, &_displayCount) != kCGErrorSuccess) {
        NSLog(@"CGGetOnlineDisplayList Error.");
        return CGSizeZero;
    }

    _allScreenSizes = malloc(maxDisplays);
    _perfectSize = CGSizeZero;
    for (uint32_t i = 0; i < _displayCount; i++) {
        CGSize sz = [self getDisplayResolution:onlineDisplays[i]];
#ifndef REVERSED
        _allScreenSizes[i] = sz;
#else
        _allScreenSizes[_displayCount-1-i] = sz;
#endif
        _perfectSize.width += sz.width;
        _perfectSize.height = MAX(_perfectSize.height, sz.height);
    }
    return _perfectSize;
}

- (CGSize)getDisplayResolution:(CGDirectDisplayID)displayID {
    NSArray *allModes = (__bridge NSArray *)(CGDisplayCopyAllDisplayModes(displayID, nil));
    NSMutableArray *allRez = [[NSMutableArray alloc] init];
    CGSize maxRez = CGSizeZero;
    for (id aMode in allModes) {
        CGDisplayModeRef thisMode = (__bridge CGDisplayModeRef)(aMode);
        size_t theWidth = CGDisplayModeGetWidth(thisMode);
        size_t theHeight = CGDisplayModeGetHeight(thisMode);
        // Get the first one
        if (CGSizeEqualToSize(maxRez, CGSizeZero)) {
            maxRez = CGSizeMake(theWidth, theHeight);
        }
        NSString *theRez = [NSString stringWithFormat:@"%zux%zu", theWidth, theHeight];
        if (![allRez containsObject:theRez]) {
            [allRez addObject:theRez];
        }
    }
    NSLog(@" display deatails = %@", allRez);
    return maxRez;
}

- (void)mainThreadCompletionNotification {
    NSNotification *n = [NSNotification notificationWithName:MSBackgroundWorkerFinishedNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotification:n];
}

- (void)notifyOfCompletionInMainThread {
    [self performSelectorOnMainThread:@selector(mainThreadCompletionNotification) withObject:nil waitUntilDone:NO];
}

- (void)execute {
    CIImage *baseCIImage = [CIImage imageWithData:[baseImage TIFFRepresentation]];
    double scaleFactor = [self scaleFactorWithSize:_perfectSize withOriginalImage:baseCIImage];
    NSLog(@"Scale factor for image:%f", scaleFactor);
    
    CIImage *scaledImage = [self scaleImage:baseCIImage byFactor:scaleFactor];
    self.procText = [NSString stringWithFormat:@"%ix%i -(x%f)-> %ix%i", (int)[baseCIImage extent].size.width,  (int)[baseCIImage extent].size.height, scaleFactor, (int)[scaledImage extent].size.width, (int)[scaledImage extent].size.height];
    
    NSString *outputDirectory = [self outputDirectory];
    CGRect currentRect = CGRectZero;
    int j = _displayCount-1;
    for (int i = 0; i < _displayCount; i++) {
        // CIVector -> [x, y, w, h]
        
        CIVector *cropForScreen = [[CIVector alloc] initWithX:currentRect.origin.x Y:(int)[scaledImage extent].size.height-_allScreenSizes[j].height
                                                            Z:_allScreenSizes[j].width W:(int)[scaledImage extent].size.height];
        currentRect.origin.x += _allScreenSizes[j].width;
        CIImage *croppedImageForScreen = [self cropImage:scaledImage withRect:cropForScreen];
        NSBitmapImageRep *bitmapImage = [self bitmapImageRepForImage:croppedImageForScreen];
        NSString *directoryForOutput = [NSString stringWithFormat:@"%@/%d.tiff", outputDirectory, j];
        
        [self saveImageToFile:directoryForOutput imageRep:bitmapImage];
#ifndef REVERSED
        SystemEventsDesktop *thisDesktop = [[sysEventsBridgeApp desktops] objectAtIndex:i];
#else
        SystemEventsDesktop *thisDesktop = [[sysEventsBridgeApp desktops] objectAtIndex:(_displayCount-1-i)];
#endif
        [thisDesktop setPicture:(SystemEventsAlias *)[NSURL URLWithString:directoryForOutput]];
        j--;
    }
    
    [self notifyOfCompletionInMainThread];
}

- (NSString*)outputDirectory {
    NSString *directoryForOutput = [NSString stringWithFormat:[@"~/Pictures/MultiScape/%f" stringByExpandingTildeInPath],
                                    [[NSDate date] timeIntervalSince1970]];
        
    if(![fileManager fileExistsAtPath:[@"~/Pictures/MultiScape" stringByExpandingTildeInPath]]) {
        [fileManager createDirectoryAtPath:[@"~/Pictures/MultiScape" stringByExpandingTildeInPath] withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [fileManager createDirectoryAtPath:directoryForOutput withIntermediateDirectories:YES attributes:nil error:nil];
    
    return directoryForOutput;
}

- (CIImage* )cropImage:(CIImage *)imageToCrop withRect:(CIVector *)screenCropVector {
    CIFilter *thisCropFilter = [CIFilter filterWithName:@"CICrop"];
    [thisCropFilter setDefaults];
    [thisCropFilter setValue:screenCropVector forKey:@"inputRectangle"];
    [thisCropFilter setValue:imageToCrop forKey:@"inputImage"];
    return [thisCropFilter valueForKey:@"outputImage"];
}

- (NSBitmapImageRep *)bitmapImageRepForImage:(CIImage*)ciImage {
    NSBitmapImageRep *bitmapImageRep = nil;
    CGRect extent = [ciImage extent];
    bitmapImageRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL 
                                                             pixelsWide:extent.size.width 
                                                             pixelsHigh:extent.size.height 
                                                          bitsPerSample:8 
                                                        samplesPerPixel:4 
                                                               hasAlpha:YES
                                                               isPlanar:NO 
                                                         colorSpaceName:NSDeviceRGBColorSpace
                                                            bytesPerRow:0
                                                           bitsPerPixel:0];
    NSGraphicsContext *nsContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmapImageRep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:nsContext];
    [[NSColor clearColor] set];
    NSRectFill(NSMakeRect(0, 0, [bitmapImageRep pixelsWide], [bitmapImageRep pixelsHigh]));
    CGRect imageDestinationRect = CGRectMake(0.0, [bitmapImageRep pixelsHigh] - extent.size.height, extent.size.width, extent.size.height);
    CIContext *ciContext = [nsContext CIContext];
    [ciContext drawImage:ciImage inRect:imageDestinationRect fromRect:extent];
    [NSGraphicsContext restoreGraphicsState];
    //[NSGraphicsContext restoreGraphicsState];
    return bitmapImageRep;
}

//- (CIVector *)cropRectForScreen:(NSScreen*)screen inFullSpace:(NSRect)fullSpace {
//    NSRect thisScreenFrame = [screen frame];
//
//    float thisX = thisScreenFrame.origin.x - fullSpace.origin.x;
//    float thisY = thisScreenFrame.origin.y - fullSpace.origin.y;
//    float thisZ = thisScreenFrame.size.width;
//    float thisW = thisScreenFrame.size.height;
//    NSLog(@"thisX %f thisY %f thisZ %f thisW %f",thisX,thisY,thisZ,thisW);
//    NSLog(@"test random");
//    CIVector *thisVector = [[CIVector alloc] initWithX:thisX Y:thisY Z:thisZ W:thisW];
//    return thisVector;
//}

- (CIImage*)scaleImage:(CIImage*)imageToScale byFactor:(double)scaleFactor {
    CIFilter *scaleTransformFilter = [CIFilter filterWithName:@"CILanczosScaleTransform"];
    [scaleTransformFilter setValue:[NSNumber numberWithDouble:scaleFactor] forKey:@"inputScale"];
    [scaleTransformFilter setValue:imageToScale forKey:@"inputImage"];
    [scaleTransformFilter setValue:[NSNumber numberWithInt:1] forKey:@"inputAspectRatio"];
    
    CIImage *scaledBaseImage = [scaleTransformFilter valueForKey:@"outputImage"];
    NSLog(@"Scaled base image dimensions: %f x %f",[scaledBaseImage extent].size.width, [scaledBaseImage extent].size.height);
    return [scaleTransformFilter valueForKey:@"outputImage"];
}

- (double)scaleFactorWithSize:(CGSize)size withOriginalImage:(CIImage*)originalImage {
    CGRect baseImageRect = [originalImage extent]; 
    
    NSLog(@"\nBase Image Dimensions:\n              %f\n%f                 %f\n              %f",baseImageRect.size.height, baseImageRect.origin.x, baseImageRect.size.width, baseImageRect.origin.y);
    
    double hScale = size.width / baseImageRect.size.width;
    double vScale = size.height / baseImageRect.size.height;
    return MAX(hScale, vScale);
}

- (void)saveImageToFile:(NSString*)fileLocation
               imageRep:(NSBitmapImageRep*)outputBitmapImageRep {
    NSDictionary *properties = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:1.0], NSImageCompressionFactor, [NSNumber numberWithBool:FALSE], NSImageProgressive, nil];
    NSData *outputData = [outputBitmapImageRep representationUsingType:NSJPEGFileType properties:properties];
    [outputData writeToFile:fileLocation atomically:NO];
}

@end
