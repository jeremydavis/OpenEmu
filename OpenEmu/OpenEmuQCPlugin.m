/*
 Copyright (c) 2009, OpenEmu Team
 
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* It's highly recommended to use CGL macros instead of changing the current context for plug-ins that perform OpenGL rendering */
#import <OpenGL/CGLMacro.h>

#import "OpenEmuQCPlugin.h"
#import <Quartz/Quartz.h>
#import <OpenGL/OpenGL.h>

#import "GameCore.h"
#import "OECorePlugin.h"

#import <IOSurface/IOSurface.h>
#import <OpenGL/CGLIOSurface.h>

#import "NSString+UUID.h"

#define    kQCPlugIn_Name               @"OpenEmu"
#define    kQCPlugIn_Description        @"Wraps the OpenEmu emulator - Play NES, Gameboy, Sega, etc roms in QC"

static void _TextureReleaseCallback(CGLContextObj cgl_ctx, GLuint name, void* info)
{
	glDeleteTextures(1, &name);
}

@implementation OpenEmuQC

@synthesize persistantControllerData;

@dynamic inputRom;
@dynamic inputControllerData;
@dynamic inputVolume;
@dynamic inputSaveStatePath;
@dynamic inputLoadStatePath;
@dynamic inputPauseEmulation;
@dynamic outputImage;

+ (NSDictionary *)attributes
{
    return [NSDictionary dictionaryWithObjectsAndKeys:kQCPlugIn_Name, QCPlugInAttributeNameKey, kQCPlugIn_Description, QCPlugInAttributeDescriptionKey, nil];
}

+ (NSDictionary *)attributesForPropertyPortWithKey:(NSString*)key
{
    if([key isEqualToString:@"inputRom"]) 
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"ROM Path", QCPortAttributeNameKey, 
                @"~/relative/or/abs/path/to/rom", QCPortAttributeDefaultValueKey, 
                nil]; 
    
    if([key isEqualToString:@"inputVolume"]) 
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"Volume", QCPortAttributeNameKey, 
                [NSNumber numberWithFloat:0.5], QCPortAttributeDefaultValueKey, 
                [NSNumber numberWithFloat:1.0], QCPortAttributeMaximumValueKey,
                [NSNumber numberWithFloat:0.0], QCPortAttributeMinimumValueKey,
                nil]; 
    
    if([key isEqualToString:@"inputControllerData"])
        return [NSDictionary dictionaryWithObjectsAndKeys:@"Controller Data", QCPortAttributeNameKey, nil];
    
    // NSArray with player count in index 0, index 1 is eButton "struct" (see GameButtons.h for typedef)
    if([key isEqualToString:@"inputPauseEmulation"])
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"Pause Emulator", QCPortAttributeNameKey,
                [NSNumber numberWithBool:NO], QCPortAttributeDefaultValueKey, 
                nil];
        
    if([key isEqualToString:@"inputSaveStatePath"])
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"Save State", QCPortAttributeNameKey,
                @"~/roms/saves/save", QCPortAttributeDefaultValueKey, 
                nil];
    
    if([key isEqualToString:@"inputLoadStatePath"])
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"Load State", QCPortAttributeNameKey,
                @"~/roms/saves/save", QCPortAttributeDefaultValueKey, 
                nil];
    if([key isEqualToString:@"outputImage"])
        return [NSDictionary dictionaryWithObjectsAndKeys:@"Image", QCPortAttributeNameKey, nil];
    
    return nil;
}

+ (NSArray *)sortedPropertyPortKeys
{
    return [NSArray arrayWithObjects:@"inputRom", @"inputControllerData", @"inputVolume",
            @"inputPauseEmulation", @"inputSaveStatePath", @"inputLoadStatePath", nil]; 
}

+ (QCPlugInExecutionMode)executionMode
{
    return kQCPlugInExecutionModeProvider;
}

+ (QCPlugInTimeMode)timeMode
{
    return kQCPlugInTimeModeIdle;
}

- (id)init
{
    if(self = [super init])
    {
    }
    
    return self;
}

- (void)finalize
{
    [super finalize];
}

- (void)dealloc
{
	[self setPersistantControllerData:nil];
	[super dealloc];
}

+ (NSArray *)plugInKeys
{
    return nil;
}

- (id)serializedValueForKey:(NSString *)key;
{
    return [super serializedValueForKey:key];
}

- (void)setSerializedValue:(id)serializedValue forKey:(NSString *)key
{
    [super setSerializedValue:serializedValue forKey:key];
}

@end

@implementation OpenEmuQC (Execution)

- (BOOL)startExecution:(id<QCPlugInContext>)context
{   
	return YES;
}

- (void)enableExecution:(id<QCPlugInContext>)context
{
	if([helper isRunning])
	   [rootProxy setPauseEmulation:NO];
}

- (BOOL)execute:(id<QCPlugInContext>)context atTime:(NSTimeInterval)time withArguments:(NSDictionary *)arguments
{   
	// handle input keys changing,
	if([self didValueForInputKeyChange:@"inputRom"])
	{
		NSString* romPath;
		if ([[self.inputRom stringByStandardizingPath] isAbsolutePath])
		{
			romPath = [self.inputRom stringByStandardizingPath];
		}
		else 
		{
			romPath = [[[[context compositionURL] path] stringByDeletingLastPathComponent] stringByAppendingPathComponent:[self.inputRom stringByStandardizingPath]];
		}
		
		[self endHelperProcess];
		[self readFromURL:[NSURL fileURLWithPath:romPath]];
		
	}
		
	if([self didValueForInputKeyChange:@"inputVolume"])
		[rootProxy setVolume:self.inputVolume];
	
	if([self didValueForInputKeyChange:@"inputPauseEmulation"])
		[rootProxy setPauseEmulation:self.inputPauseEmulation];
		
	// Process controller data
	if([self didValueForInputKeyChange: @"inputControllerData"])
	{
		// hold on to the controller data, which we are going to feed gameCore every frame.  Mmmmm...controller data.
		if([self controllerDataValidate:[self inputControllerData]])
		{
			[self setPersistantControllerData:[self inputControllerData]]; 
			
			[self handleControllerData];
		}
	}    
	
	// according to CGLIOSurface we must rebind our texture every time we want a new stuff from it.
	// since our ID may change every frame we make a new texture each pass. 
	
	//	NSLog(@"Surface ID: %u", (NSUInteger) surfaceID);
	
	IOSurfaceRef surfaceRef = NULL;
	IOSurfaceID surfaceID = 0;
	if(rootProxy != nil)
	{
		surfaceID = [rootProxy surfaceID];
		// WHOA - This causes a retain.
		surfaceRef = IOSurfaceLookup(surfaceID);
	}
	
	// get our IOSurfaceRef from our passed in IOSurfaceID from our background process.
	if(surfaceRef)
	{			
		CGLContextObj cgl_ctx = [context CGLContextObj];
		
		glPushAttrib(GL_ALL_ATTRIB_BITS);
		GLuint captureTexture;
		glGenTextures(1, &captureTexture);
		glEnable(GL_TEXTURE_RECTANGLE_ARB);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, captureTexture);
		
		CGLError err = CGLTexImageIOSurface2D(cgl_ctx, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA8, IOSurfaceGetWidth(surfaceRef), IOSurfaceGetHeight(surfaceRef), GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, surfaceRef, 0);
		if(err != kCGLNoError)
		{
			NSLog(@"Error creating IOSurface texture: %s & %x", CGLErrorString(err), glGetError());
		}
		
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, 0);
		glDisable(GL_TEXTURE_RECTANGLE_ARB);
		glPopAttrib();
				
		self.outputImage = [context outputImageProviderFromTextureWithPixelFormat:QCPlugInPixelFormatBGRA8 pixelsWide:IOSurfaceGetWidth(surfaceRef) pixelsHigh:IOSurfaceGetHeight(surfaceRef) name:captureTexture flipped:NO releaseCallback:_TextureReleaseCallback releaseContext:nil colorSpace:[context colorSpace] shouldColorMatch:YES];
		
		// release the surface 
		CFRelease(surfaceRef);	
	}
	else 
		self.outputImage = nil;

	return YES;
}

- (void)disableExecution:(id<QCPlugInContext>)context
{
	[rootProxy setPauseEmulation:YES];
}

- (void)stopExecution:(id<QCPlugInContext>)context
{
	if([helper isRunning])
		[self endHelperProcess];
}


#pragma mark Helper Process
- (BOOL)startHelperProcess
{
	// run our background task. Get our IOSurface ids from its standard out.
	NSString *cliPath = [[NSBundle bundleForClass:[self class]] pathForResource: @"OpenEmuHelperApp" ofType: @""];
	
	// generate a UUID string so we can have multiple screen capture background tasks running.
	taskUUIDForDOServer = [[NSString stringWithUUID] retain];
	// NSLog(@"helper tool UUID should be %@", taskUUIDForDOServer);
	
	NSArray *args = [NSArray arrayWithObjects: cliPath, taskUUIDForDOServer, nil];
	
	helper = [[OETaskWrapper alloc] initWithController:self arguments:args userInfo:nil];
	[helper startProcess];
	
	if(![helper isRunning])
	{
		[helper release];
//		if(outError != NULL)
//			*outError = [NSError errorWithDomain:OEGameDocumentErrorDomain
//											code:OEHelperAppNotRunningError
//										userInfo:[NSDictionary dictionaryWithObject:NSLocalizedString(@"The background process couldn't be launched", @"Not running background process error") forKey:NSLocalizedFailureReasonErrorKey]];
		return NO;
	}
	
	// now that we launched the helper, start up our NSConnection for DO object vending and configure it
	// this is however a race condition if our helper process is not fully launched yet. 
	// we hack it out here. Normally this while loop is not noticable, its very fast
	
	NSDate *start = [NSDate date];
	
	taskConnection = nil;
	while(taskConnection == nil)
	{
		taskConnection = [NSConnection connectionWithRegisteredName:[NSString stringWithFormat:@"com.openemu.OpenEmuHelper-%@", taskUUIDForDOServer, nil] host:nil];
		
		if(-[start timeIntervalSinceNow] > 3.0)
		{
			[self endHelperProcess];
			return NO;
		}
	}
	
	[taskConnection retain];
	
	if(![taskConnection isValid])
	{
		[self endHelperProcess];
		return NO;
	}
	
	// now that we have a valid connection...
	rootProxy = [[taskConnection rootProxy] retain];
	if(rootProxy == nil)
	{
		NSLog(@"nil root proxy object?");
		[self endHelperProcess];
		return NO;
	}
	
	[(NSDistantObject *)rootProxy setProtocolForProxy:@protocol(OEGameCoreHelper)];
	
	return YES;
}

- (void)endHelperProcess
{       
    [rootProxy release];
    rootProxy = nil;
    
	// kill our background friend
    while([helper isRunning])
		[helper stopProcess];
    
	helper = nil;	
	
	[taskConnection invalidate];
    [taskConnection release];
    taskConnection = nil;
}

#pragma mark Loading

- (OECorePlugin *)OE_pluginForFileExtension:(NSString *)ext
{
    OECorePlugin *ret = nil;
    
    NSArray *validPlugins = [OECorePlugin pluginsForFileExtension:ext];
    
    //if([validPlugins count] <= 1)
		ret = [validPlugins lastObject];
  
    return ret;
}		 
		 
- (BOOL)readFromURL:(NSURL *)absoluteURL
{
    NSString *romPath = [absoluteURL path];
    if([[NSFileManager defaultManager] fileExistsAtPath:romPath])
    {        
        OECorePlugin *plugin = [self OE_pluginForFileExtension:[absoluteURL pathExtension]];
        
        if(plugin == nil) return NO;
        
        //emulatorName = [[plugin displayName] retain];
        
        if([self startHelperProcess])
        {			
            if([rootProxy loadRomAtPath:romPath withCorePluginAtPath:[[plugin bundle] bundlePath] owner:nil])
            {
                [rootProxy setupEmulation];
                
                return YES;
            }
        }
    }
//    else if(outError != NULL)
//    {
//        *outError = [NSError errorWithDomain:OEGameDocumentErrorDomain
//                                        code:OEFileDoesNotExistError
//                                    userInfo:
//                     [NSDictionary dictionaryWithObjectsAndKeys:
//                      NSLocalizedString(@"The file you selected doesn't exist", @"Inexistent file error reason."),
//                      NSLocalizedFailureReasonErrorKey,
//                      NSLocalizedString(@"Choose a valid file.", @"Inexistent file error recovery suggestion."),
//                      NSLocalizedRecoverySuggestionErrorKey,
//                      nil]];
//    }
    
    return NO;
}			

#pragma mark Controller

- (BOOL)controllerDataValidate:(NSArray *)cData
{
    // sanity check
    if([cData count] == 2 && [[cData objectAtIndex:1] count] == 30)
    {
        //NSLog(@"validated controller data");
        return YES;
    }    
    NSLog(@"error: missing or invalid controller data structure.");
    return NO;
}

- (void) handleControllerData
{
    // iterate through our NSArray of controller data. We know the player, we know the structure.
    // pull it out, and hand it off to our gameCore
    
    // player number 
    NSNumber*  playerNumber = [persistantControllerData objectAtIndex:0];
    NSArray * controllerArray = [persistantControllerData objectAtIndex:1];
    
    NSUInteger i;
    for(i = 0; i < [controllerArray count]; i++)
    {
        if(i > 5 && i < 10)
            continue;
        //       NSLog(@"index is %u", i);
        if([[controllerArray objectAtIndex:i] boolValue] == TRUE) // down
        {
            //    NSLog(@"button %u is down", i);
            //    [gameCore buttonPressed:i forPlayer:[playerNumber intValue]];
            [rootProxy player:[playerNumber intValue] didPressButton:(i + 1)];
        }        
        else if([[controllerArray objectAtIndex:i] boolValue] == FALSE) // up
        {
            //    NSLog(@"button %u is up", i);
            //    [gameCore buttonRelease:i forPlayer:[playerNumber intValue]];
            [rootProxy player:[playerNumber intValue] didReleaseButton:(i + 1)];
        }
    } 
}

	
#pragma mark TaskWrapper delegates

- (void)appendOutput:(NSString *)output fromProcess: (OETaskWrapper *)aTask
{
}	

- (void)processStarted: (OETaskWrapper *)aTask
{
}

- (void)processFinished: (OETaskWrapper *)aTask withStatus: (int)statusCode
{
	
}

@end
