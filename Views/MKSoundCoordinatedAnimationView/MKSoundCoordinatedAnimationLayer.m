//
//  MKSoundCoordinatedAnimationLayer.m
//  
// Copyright 2010 Michael F. Kamprath
// michael@claireware.com
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <AVFoundation/AVFoundation.h>
#import "MKSoundCoordinatedAnimationLayer.h"

NSString* const kSCANSoundFileNameKey = @"soundFile";
NSString* const kSCANImageFileNameKey = @"imageFile";

NSString* const kSCANSoundObjectKey = @"soundObj";
NSString* const kSCANImageObjectKey = @"imageObj";
NSString* const kSCANLastFrameDurationKey = @"lastFrameDuration";


@interface MKSoundCoordinatedAnimationLayer ()

- (void)initValues;

- (void)playCurrentFrame;
- (void)playCurrentFrameAndQueueNextFrame;
- (void)playNextFrame:(NSTimer*)theTimer;


@end


@interface MKDefaultAnimationObjectFactory : NSObject <MKSoundCoordinatedAnimationObjectFactory>
{
	
}

-(UIImage*)getUIImageForFilename:(NSString*)inFilename;
-(AVAudioPlayer*)getAVAudioPlayerForFilename:(NSString*)inFilename;

@end



@implementation MKSoundCoordinatedAnimationLayer
@synthesize config=_config;
@synthesize stillImage=_stillImage;
@synthesize timeScaleFactor=_timeScaleFactor;
@dynamic duration;
@dynamic isAnimating;
@synthesize silenced=_silenced;


- (id)init
{
	if ( self = [super init] )
	{
		[self initValues];
	}
	
	return self;
}

- (id)initWithLayer:(id)layer
{
	if ( self = [super initWithLayer:layer] )
	{
		[self initValues];
	}
	
	return self;
}

- (void)initValues
{
	self.timeScaleFactor = 1.0;
	
}

- (void)dealloc 
{
	[_config release];
	[_stillImage release];
	[_currentFrameImage release];
	[_sortedFrameKeys release];
	
	
    [super dealloc];
}


- (void)drawInContext:(CGContextRef)inContext
{
	CGContextScaleCTM( inContext, 1, -1 );
	CGContextTranslateCTM( inContext, 0, -self.bounds.size.height );
	
    if ( self.isAnimating && ( _currentFrameImage != nil ) )
	{
		CGContextDrawImage( inContext, self.bounds, _currentFrameImage.CGImage );
	}
	else if ( self.stillImage != nil )
	{
		CGContextDrawImage( inContext, self.bounds, self.stillImage.CGImage );
	}
}


#pragma mark -- Properties --

-(void)setConfig:(NSDictionary *)inConfig
{
	[self stopAnimatingImmeditely:YES];
	
	if (_config != nil )
	{
		[_config release];
		_config = nil;
		
		[_sortedFrameKeys release];
		_sortedFrameKeys = nil;
	}
	
	_config = [inConfig retain];
	
	for ( NSNumber* timeKey in _config )
	{
		NSDictionary* datum = [_config objectForKey:timeKey];
		
		AVAudioPlayer* sound = [datum objectForKey:kSCANSoundObjectKey];
		
		if ( sound != nil )
		{
			[sound prepareToPlay];
		}
	}
	
	NSArray* keys = [_config allKeys];
	
	_sortedFrameKeys = [[keys sortedArrayUsingSelector:@selector(compare:)] retain];
	
}

-(void)setStillImage:(UIImage *)inImage
{
	if (_stillImage == nil)
	{
		[_stillImage release];
		_stillImage = nil;
	}
	
	if (inImage != nil)
	{
		_stillImage = [inImage retain];
	}
	
}

- (NSTimeInterval)animationSequenceDuration
{
	if ((self.config != nil)&&( self.config.count > 0 ))
	{
		NSTimeInterval maxTime = 0;
		
		for ( NSNumber* timeKey in self.config )
		{
			NSTimeInterval timeKeyValue = [timeKey doubleValue]*self.timeScaleFactor;
			if ( timeKeyValue > maxTime )
			{
				maxTime = timeKeyValue;
			}
			
			
			NSDictionary* datum = [self.config objectForKey:timeKey];
			
			AVAudioPlayer* sound = [datum objectForKey:kSCANSoundObjectKey];
			
			if ( sound != nil )
			{
				NSTimeInterval frameEndTime = timeKeyValue + sound.duration;
				
				if ( frameEndTime > maxTime )
				{
					maxTime = frameEndTime;
				}
			}
			
			NSNumber* lastFrameTime = [datum objectForKey:kSCANLastFrameDurationKey];
			
			if ( lastFrameTime != nil )
			{
				NSTimeInterval frameEndTime = timeKeyValue + ([lastFrameTime doubleValue])*self.timeScaleFactor;
				
				if ( frameEndTime > maxTime )
				{
					maxTime = frameEndTime;
				}
			}
			
		}
		
		return maxTime;
	}
	else 
	{
		return 0;
	}
	
}

- (BOOL)isAnimating
{
	
	return (_animationLoopCount != 0);
}

#pragma mark -- Public Methods --

-(void)startAnimating
{
	//
	// NSUIntegerMax is  sentinal value indicating to cycle animaitons with no end
	//
	
	[self startAnimatingWithCycleCount:NSUIntegerMax];
}

// starts the animation sequence looping for a specific number of counts. 
// Passing 0 cycle count value has no effect. If called while animating, will set the 
// remining loop counter to passed value after current loop finishes. 
-(void)startAnimatingWithCycleCount:(NSUInteger)inCycleCount
{
	_animationLoopCount = inCycleCount;
	
	_currentFrameKeyIndex = 0;
	
	[self playCurrentFrameAndQueueNextFrame];
}



// Stops the animation, either immediately or after the end of the current loop.
-(void)stopAnimatingImmeditely:(BOOL)inImmediately
{
	if (inImmediately)
	{
		if (_timer != nil)
		{
			[_timer invalidate];
			[_timer release];
			_timer = nil;
		}
		[_currentFrameImage release];
		_currentFrameImage = nil;
		
		_animationLoopCount = 0;
		
		[self setNeedsDisplay];
	}
	else 
	{
		_animationLoopCount = 1;
	}
}

#pragma mark -- Class Methods --



+(NSDictionary*)configFromPropertList:(NSDictionary*)inPropertyList
{
	if (inPropertyList == nil)
	{
		return nil;
	}
	
	MKDefaultAnimationObjectFactory* objectFactory = [[MKDefaultAnimationObjectFactory alloc] init];
	
	NSDictionary* config = [MKSoundCoordinatedAnimationLayer configFromPropertList:inPropertyList usingObjectFactory:objectFactory];

	[objectFactory release];
	
	return config;
}


//
// converts a "property list" configuration dictionary to the format expected by the config property of an instance.
// The "property list" verison of the configuraiton does not contain sound or image objects, but in stead filenames.
// This method will generate a config dictionary containin the sound and image objects based. Useful for configuring
// an animation with a plist file.
// The property list format is:
//
// key = NSNumber containing a float value indicating he number of seconds since start this item should be applied
// value = a dictionary containing one or more of the following key/value pairs
//					key		         | value
//				---------------------+------------------------------------------------------------
//				 "soundFile"	     | the file name a sound file, including extension (NSString)
//				 "imageFile"	     | the file name of an image, inclding extension (NSString)
//				 "lastFrameDuration" | If this is the last frame, a NSNumber indicating the minimum duration of frame.
//								     | Note that animation will not cycle until all sounds initated in current cycle are complete.
//

+(NSDictionary*)configFromPropertList:(NSDictionary*)inPropertyList usingObjectFactory:(id <MKSoundCoordinatedAnimationObjectFactory>)inObjectFactory
{
	if (inPropertyList == nil)
	{
		return nil;
	}
	
	NSMutableDictionary* configDict = [NSMutableDictionary dictionaryWithCapacity:[inPropertyList count]];
	
	for ( NSNumber* timeKey in inPropertyList )
	{
		NSDictionary* frameProperties = [inPropertyList objectForKey:timeKey];
		
		NSMutableDictionary* frameConfig = [NSMutableDictionary dictionaryWithCapacity:[frameProperties count]];
		
		NSString* soundFileName = [frameProperties objectForKey:kSCANSoundFileNameKey];
		
		AVAudioPlayer *player = [inObjectFactory getAVAudioPlayerForFilename:soundFileName];
		
		if (player != nil)
		{
			[frameConfig setObject:player forKey:kSCANSoundObjectKey];
		}

		
		NSString* imageFileName = [frameProperties objectForKey:kSCANImageFileNameKey];
		
		UIImage* image = [inObjectFactory getUIImageForFilename:imageFileName];
		
		if (image != nil)
		{
			[frameConfig setObject:image forKey:kSCANImageObjectKey];
		}
		
		id durationObj = [frameProperties objectForKey:kSCANLastFrameDurationKey];
		
		if ( durationObj != nil )
		{
			[frameConfig setObject:durationObj forKey:kSCANLastFrameDurationKey];
		}
		
		[configDict setObject:frameConfig forKey:timeKey];
	}
	
	return configDict;
	
	
}

//
// UIImage objects can shared between multiple instnaces of a given animation, but AVAudioPlayer objects
// cannot because each animation instance may have a different play state. This method will "copy" a config
// dictionary by producing an (autoreleased) copy of it where the UIImage objects are shared by the 
// AVAudioPlayer objects are distinct copies. 
+(NSDictionary*)copyConfig:(NSDictionary*)inConfig
{
	NSMutableDictionary* newConfigDict = [NSMutableDictionary dictionaryWithCapacity:[inConfig count]];
	
	for ( NSNumber* timeKey in inConfig )
	{
		NSDictionary* sourceFrameConfig = [inConfig objectForKey:timeKey];
		
		NSMutableDictionary* frameConfig = [NSMutableDictionary dictionaryWithCapacity:[sourceFrameConfig count]];
		
		//
		// create a new sound object
		//
		AVAudioPlayer* soundObj = [sourceFrameConfig objectForKey:kSCANSoundObjectKey];
		if ( soundObj != nil )
		{
			AVAudioPlayer* newSoundObj;
			
			if ( soundObj.url != nil )
			{
				NSError* sndErr;
				
				newSoundObj = [[AVAudioPlayer alloc] initWithContentsOfURL:soundObj.url error:&sndErr];
				
				if ( sndErr != nil )
				{
					NSLog(@"Error creating AVAudioPlayer with URL '%@': %@", soundObj.url, [sndErr localizedDescription]);
					
					newSoundObj = nil;
				}
			}
			else if ( soundObj.data != nil )
			{
				NSError* sndErr;
				
				newSoundObj = [[AVAudioPlayer alloc] initWithData:soundObj.data error:&sndErr];
				
				
				if ( sndErr != nil )
				{
					NSLog(@"Error creating AVAudioPlayer from source data: %@", [sndErr localizedDescription]);
					
					newSoundObj = nil;
				}
				
			}
			
			if ( newSoundObj != nil )
			{
				[frameConfig setObject:newSoundObj forKey:kSCANSoundObjectKey];
			}
		}
		
		id imageObj = [sourceFrameConfig objectForKey:kSCANImageObjectKey];
		
		if ( imageObj != nil )
		{
			[frameConfig setObject:imageObj forKey:kSCANImageObjectKey];
		}
		
		id durationObj = [sourceFrameConfig objectForKey:kSCANLastFrameDurationKey];
		
		if ( durationObj != nil )
		{
			[frameConfig setObject:durationObj forKey:kSCANLastFrameDurationKey];
		}
		
		
		[newConfigDict setObject:frameConfig forKey:timeKey];
	}
	
	return newConfigDict;
	
}

#pragma mark -- Private Methods -- 

- (void)playCurrentFrame
{
	NSDictionary* datum = [self.config objectForKey:[_sortedFrameKeys objectAtIndex:_currentFrameKeyIndex]];
	
	UIImage* image = [datum objectForKey:kSCANImageObjectKey];
	
	if (image != nil )
	{
		[_currentFrameImage release];
		_currentFrameImage = [image retain];
		
		[self setNeedsDisplay];
	}
	
	if (!self.isSilenced)
	{
		AVAudioPlayer* sound = [datum objectForKey:kSCANSoundObjectKey];
		
		if (sound != nil)
		{
			[sound play];
		}
	}
}

- (void)playCurrentFrameAndQueueNextFrame
{
	[self playCurrentFrame];
	
	NSTimeInterval frameDuration = 0;
	
	NSNumber* currentTimeKey = [_sortedFrameKeys objectAtIndex:_currentFrameKeyIndex];
	
	if ( _currentFrameKeyIndex + 1 < _sortedFrameKeys.count )
	{
		NSNumber* nextTimeKey =  [_sortedFrameKeys objectAtIndex:(_currentFrameKeyIndex+1)];
		
		frameDuration = [nextTimeKey doubleValue] - [currentTimeKey floatValue];
	}
	else if ( _currentFrameKeyIndex + 1 == _sortedFrameKeys.count )
	{
		NSDictionary* datum = [self.config objectForKey:currentTimeKey];
		
		NSNumber* lastFrameDuration = [datum objectForKey:kSCANLastFrameDurationKey];
		
		if ( lastFrameDuration != nil )
		{
			frameDuration = [lastFrameDuration floatValue];
		}
	}
	
	frameDuration *= self.timeScaleFactor;
	
	_timer = [[NSTimer scheduledTimerWithTimeInterval:frameDuration target:self selector:@selector(playNextFrame:) userInfo:nil repeats:NO] retain];
}

- (void)playNextFrame:(NSTimer*)theTimer
{
	[_timer release];
	_timer = nil;
	
	_currentFrameKeyIndex++;
	
	if ( _currentFrameKeyIndex == _sortedFrameKeys.count )
	{
		if ((_animationLoopCount != NSUIntegerMax)&&( _animationLoopCount > 0 ))
		{
			_animationLoopCount--;
		}
		_currentFrameKeyIndex = 0;
	}
	
	if ( _animationLoopCount > 0 )
	{
		[self playCurrentFrameAndQueueNextFrame];
	}
}

@end

@implementation MKDefaultAnimationObjectFactory

-(UIImage*)getUIImageForFilename:(NSString*)inFilename
{
	if (inFilename != nil)
	{
		NSString* pathStr;
		
		
		//
		// if it is desired to load a specific localization, this code will need to be altered to use [NSBundle pathForResource:ofType:inDirectory:forLocalization:]
		//
		
		pathStr = [[NSBundle mainBundle] pathForResource:inFilename ofType:nil];	
		
		if ( pathStr != nil )
		{
			UIImage* image = [UIImage imageWithContentsOfFile:pathStr];
			
			if ( image != nil )
			{
				return image;
			}
			else 
			{
				NSLog( @"Could not create image with file path '%@'", pathStr );
			}
		}
	}
	
	return nil;
}

-(AVAudioPlayer*)getAVAudioPlayerForFilename:(NSString*)inFilename
{
	
	if ( inFilename != nil )
	{
		
		NSString* pathStr;
		
		
		//
		// if it is desired to load a specific localization, this code will need to be altered to use [NSBundle pathForResource:ofType:inDirectory:forLocalization:]
		//
		
		pathStr = [[NSBundle mainBundle] pathForResource:inFilename ofType:nil];	
		
		if ( pathStr != nil )
		{
			NSError* sndErr;
			
			NSURL *fileURL = [NSURL fileURLWithPath:pathStr isDirectory:NO];
			
			AVAudioPlayer *player = [[ AVAudioPlayer alloc ] initWithContentsOfURL:fileURL error:(&sndErr) ];
			
			[[ AVAudioPlayer alloc ] initWithContentsOfURL:fileURL error:(&sndErr) ];
			
			if (sndErr == nil)
			{
				return player;
			}
			else
			{
				NSLog(@"Error creating AVAudioPlayer with file path '%@': %@", pathStr, [sndErr localizedDescription]);
			}
		}	
	}
	
	return nil;
}	


@end
