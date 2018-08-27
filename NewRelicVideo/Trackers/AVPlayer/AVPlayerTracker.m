//
//  AVPlayerTracker.m
//  NewRelicVideo
//
//  Created by Andreu Santaren on 23/08/2018.
//  Copyright © 2018 New Relic Inc. All rights reserved.
//

#import "AVPlayerTracker.h"
#import "TrackerAutomat.h"

// TODO: if autoplay, qe have to manually send the transition AUTOPLAY
// TODO: if time period event arrives (addPeriodicTimeObserverForInterval) and rate == 0 we are seeking??
// BUG: if we seek until the end, the VIDEO FINISHED never arrives. Possible workaround: after getting a timevent with rate = 0, wait for a timevent with rate = 1, if timeout fire the video finshed event.

@import AVKit;

@interface AVPlayerTracker ()

@property (nonatomic) TrackerAutomat *automat;

// AVPlayer weak reference
@property (nonatomic, weak) AVPlayer *player;

@end

@implementation AVPlayerTracker

- (instancetype)initWithAVPlayer:(AVPlayer *)player {
    if (self = [super init]) {
        self.player = player;
        self.automat = [[TrackerAutomat alloc] init];
    }
    return self;
}

- (void)reset {}

- (void)setup {
    
    // Register periodic time observer (an event every 1/2 seconds)
    
    [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2) queue:NULL usingBlock:^(CMTime time) {
        double currentTime = (double)time.value / (double)time.timescale;
        NSLog(@"Current playback rate = %f, time = %lf", self.player.rate, currentTime);
    }];
    
    // Register NSNotification listeners
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(itemTimeJumpedNotification:)
                                                 name:AVPlayerItemTimeJumpedNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(itemDidPlayToEndTimeNotification:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:nil];
    
    // Register KVO events
    
    [self.player addObserver:self forKeyPath:@"rate"
                     options:NSKeyValueObservingOptionNew
                     context:NULL];
    
    [self.player.currentItem addObserver:self forKeyPath:@"playbackBufferEmpty"
                                 options:NSKeyValueObservingOptionNew
                                 context:NULL];
    
    [self.player.currentItem addObserver:self forKeyPath:@"playbackBufferFull"
                                 options:NSKeyValueObservingOptionNew
                                 context:NULL];
    
    [self.player.currentItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp"
                                 options:NSKeyValueObservingOptionNew
                                 context:NULL];
}

- (NSTimeInterval)epoch {
    return [[NSDate date] timeIntervalSince1970];
}

#pragma mark - Item Handlers

- (void)itemTimeJumpedNotification:(NSNotification *)notification {
    
    AVPlayerItem *p = [notification object];
    NSString *statusStr = @"";
    switch (p.status) {
        case AVPlayerItemStatusFailed:
            statusStr = @"Failed";
            break;
        case AVPlayerItemStatusUnknown:
            statusStr = @"Unknown";
            break;
        case AVPlayerItemStatusReadyToPlay:
            statusStr = @"Ready";
            break;
        default:
            break;
    }
    NSLog(@"ItemTimeJumpedNotification = %@", statusStr);
    
    if (p.status == AVPlayerItemStatusReadyToPlay) {
        [self.automat transition:TrackerTransitionFrameShown];
    }
    else if (p.status == AVPlayerItemStatusFailed) {
        NSLog(@"#### ERROR WHILE PLAYING");
        // NOTE: this is probably redundant and already catched in "rate" KVO when self.player.error != nil
    }
}

- (void)itemDidPlayToEndTimeNotification:(NSNotification *)notification {
    NSLog(@"ItemDidPlayToEndTimeNotification");
    NSLog(@"#### FINISHED PLAYING");
    // NOTE: this is redundant and already catched in "rate" KVO
}

// KVO observer method
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context {
    
    if ([keyPath isEqualToString:@"rate"]) {
        
        float rate = [(NSNumber *)change[NSKeyValueChangeNewKey] floatValue];
        
        if (rate == 0.0) {
            NSLog(@"Video Rate Log: Stopped Playback");
            
            if (self.player.error != nil) {
                NSLog(@"  -> Playback Failed");
                [self.automat transition:TrackerTransitionErrorPlaying];
            }
            else if (CMTimeGetSeconds(self.player.currentTime) >= CMTimeGetSeconds(self.player.currentItem.duration)) {
                NSLog(@"  -> Playback Reached the End");
                [self.automat transition:TrackerTransitionVideoFinished];
            }
            else if (!self.player.currentItem.playbackLikelyToKeepUp) {
                // NOTE: it never happens
                NSLog(@"  -> Playback Waiting Data");
            }
            else {
                // Click Pause
                [self.automat transition:TrackerTransitionClickPause];
            }
        }
        else if (rate == 1.0) {
            NSLog(@"Video Rate Log: Normal Playback");
            
            // Click Play
            [self.automat transition:TrackerTransitionClickPlay];
        }
        else if (rate == -1.0) {
            NSLog(@"Video Rate Log: Reverse Playback");
        }
    }
    else if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {
        NSLog(@"Video Playback Buffer Empty");
        
        [self.automat transition:TrackerTransitionInitBuffering];
    }
    else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
        NSLog(@"Video Playback Likely To Keep Up");
        
        [self.automat transition:TrackerTransitionEndBuffering];
    }
    else if ([keyPath isEqualToString:@"playbackBufferFull"]) {
        NSLog(@"Video Playback Buffer Full");

        [self.automat transition:TrackerTransitionEndBuffering];
    }
    else {
        NSLog(@"OBSERVER unknown = %@", keyPath);
    }
}

@end
