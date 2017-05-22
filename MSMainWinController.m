//
//  MSMainWinController.m
//  MultiScape
//
//  Created by David Zwerdling on 12/20/08.
//  Copyright 2010 Laughing Man Software. All rights reserved.
//  This file is part of MultiScape.
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


#import "MSMainWinController.h"
#import "MSBackgroundWorker.h"

@interface MSMainWinController () {
    NSImage * _baseImage;
    MSBackgroundWorker *_worker;
}

- (void) notifyOfCompletedBackgroundExecution:(NSNotification*)notif;

@end

@implementation MSMainWinController

@synthesize baseImage = _baseImage;

#pragma mark Initialization Methods
- (void)awakeFromNib {
    _worker = [[MSBackgroundWorker alloc] init];
    CGSize sz = [_worker perfectSize];
    [sizeLabel setStringValue:[NSString stringWithFormat:@"%.0f x %.0f", sz.width, sz.height]];
}

#pragma mark Main Execute Methods
- (void)setBaseImage:(NSImage*)imageToSet {
    _baseImage = imageToSet;
    NSLog(@"Input image changed");
    [self executeForImage: imageToSet];
}

- (void)notifyOfCompletedBackgroundExecution:(NSNotification*)notif {
    if([notif object] == _worker) {
        [infoField setStringValue:_worker.procText];
    }
}

- (void)executeForImage:(NSImage*)startImage {
    if (baseImageView.image) {
        _worker.baseImage = startImage;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notifyOfCompletedBackgroundExecution:)
                                                     name:MSBackgroundWorkerFinishedNotification object:_worker];
        [_worker execute];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MSBackgroundWorkerFinishedNotification object:_worker];
    [NSApp terminate:self];
}

@end
