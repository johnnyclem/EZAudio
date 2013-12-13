//
//  EZRecorder.m
//  EZAudioExample-OSX
//
//  Created by Syed Haris Ali on 12/1/13.
//  Copyright (c) 2013 Syed Haris Ali. All rights reserved.
//

#import "EZRecorder.h"

#import "../EZAudio.h"

@interface EZRecorder (){
  AudioConverterRef           _audioConverter;
  AudioStreamBasicDescription _clientFormat;
  ExtAudioFileRef             _destinationFile;
  CFURLRef                    _destinationFileURL;
  AudioStreamBasicDescription _destinationFormat;
  AudioStreamBasicDescription _sourceFormat;
}

typedef struct {
  AudioBufferList *sourceBuffer;
} EZRecorderConverterStruct;

@end

@implementation EZRecorder

#pragma mark - Initializers
-(EZRecorder*)initWithDestinationURL:(NSURL*)url
                   destinationFormat:(AudioStreamBasicDescription)destinationFormat
                     andSourceFormat:(AudioStreamBasicDescription)sourceFormat {
  self = [super init];
  if(self){
    _destinationFileURL = (__bridge CFURLRef)url;
    _sourceFormat = sourceFormat;
    _destinationFormat = destinationFormat;
    [self _configureRecorder];
  }
  return self;
}

#pragma mark - Class Initializers
+(EZRecorder*)recorderWithDestinationURL:(NSURL*)url
                       destinationFormat:(AudioStreamBasicDescription)destinationFormat
                         andSourceFormat:(AudioStreamBasicDescription)sourceFormat {
  return [[EZRecorder alloc] initWithDestinationURL:url
                                  destinationFormat:destinationFormat
                                    andSourceFormat:sourceFormat];
}

#pragma mark - Class Format Helper
+(AudioStreamBasicDescription)defaultDestinationFormat {
  AudioStreamBasicDescription destinationFormat;
  destinationFormat.mFormatID = kAudioFormatLinearPCM;
  destinationFormat.mChannelsPerFrame = 1;
  destinationFormat.mBitsPerChannel = 16;
  destinationFormat.mBytesPerPacket = destinationFormat.mBytesPerFrame = 2 * destinationFormat.mChannelsPerFrame;
  destinationFormat.mFramesPerPacket = 1;
  destinationFormat.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
  destinationFormat.mSampleRate = 44100.0;
  return destinationFormat;
}

+(NSString *)defaultDestinationFormatExtension {
  return @"caf";
}

#pragma mark - Private Configuation
-(void)_configureRecorder {
  
  // Create the extended audio file
  [EZAudio checkResult:ExtAudioFileCreateWithURL(_destinationFileURL,
                                                 kAudioFileCAFType,
                                                 &_destinationFormat,
                                                 NULL,
                                                 kAudioFileFlags_EraseFile,
                                                 &_destinationFile)
             operation:"Failed to create ExtendedAudioFile reference"];
  
  // Set the client format
  _clientFormat = _destinationFormat;
  if( _destinationFormat.mFormatID != kAudioFormatLinearPCM ){
    [EZAudio setCanonicalAudioStreamBasicDescription:_destinationFormat
                                    numberOfChannels:_destinationFormat.mChannelsPerFrame
                                         interleaved:YES];
  }
  
  UInt32 propertySize = sizeof(_clientFormat);
  [EZAudio checkResult:ExtAudioFileSetProperty(_destinationFile,
                                               kExtAudioFileProperty_ClientDataFormat,
                                               propertySize,
                                               &_clientFormat)
             operation:"Failed to set client data format on destination file"];
  
  // Setup the audio converter
  [EZAudio checkResult:AudioConverterNew(&_sourceFormat, &_destinationFormat, &_audioConverter)
             operation:"Failed to create new audio converter"];
  
}

#pragma mark - Events
-(void)appendDataFromBufferList:(AudioBufferList*)bufferList
                 withBufferSize:(UInt32)bufferSize {
  
  // Setup output buffers
  UInt32 outputBufferSize = 32 * 1024; // 32 KB
  AudioBufferList convertedData;
  convertedData.mNumberBuffers = 1;
  convertedData.mBuffers[0].mNumberChannels = _clientFormat.mChannelsPerFrame;
  convertedData.mBuffers[0].mDataByteSize   = outputBufferSize;
  convertedData.mBuffers[0].mData           = (UInt8 *)malloc(sizeof(UInt8)*outputBufferSize);
  
  [EZAudio checkResult:AudioConverterFillComplexBuffer(_audioConverter,
                                                       complexInputDataProc,
                                                       &(EZRecorderConverterStruct){ .sourceBuffer = bufferList },
                                                       &bufferSize,
                                                       &convertedData,
                                                       NULL) operation:"Failed while converting buffers"];
  
  // Write the destination audio buffer list into t
  [EZAudio checkResult:ExtAudioFileWriteAsync(_destinationFile, bufferSize, &convertedData)
             operation:"Failed to write audio data to file"];
  
}

static OSStatus complexInputDataProc(AudioConverterRef             inAudioConverter,
                                     UInt32                        *ioNumberDataPackets,
                                     AudioBufferList               *ioData,
                                     AudioStreamPacketDescription  **outDataPacketDescription,
                                     void                          *inUserData) {
  EZRecorderConverterStruct *recorderStruct = (EZRecorderConverterStruct*)inUserData;
  
  if ( !recorderStruct->sourceBuffer ) {
    return -2222; // No More Data
  }

  memcpy(ioData,
         recorderStruct->sourceBuffer,
         sizeof(AudioBufferList) + (recorderStruct->sourceBuffer->mNumberBuffers-1)*sizeof(AudioBuffer));
  recorderStruct->sourceBuffer = NULL;
  
  return noErr;
}

#pragma mark - Cleanup
-(void)dealloc {
  [EZAudio checkResult:AudioConverterDispose(_audioConverter)
             operation:"Failed to dispose audio converter in recorder"];
  [EZAudio checkResult:ExtAudioFileDispose(_destinationFile)
             operation:"Failed to dispose extended audio file in recorder"];
}

@end