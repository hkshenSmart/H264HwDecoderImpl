//
//  LMHardwareVideoEncoder.m
//  V5ConferenceiOSLib
//
//  Created by shenkun on 16/6/16.
//  Copyright © 2016年 guanjianchuang. All rights reserved.
//

#import "LMHardwareVideoEncoder.h"
#import <VideoToolbox/VideoToolbox.h>

@interface LMHardwareVideoEncoder (){
    VTCompressionSessionRef compressionSession;
    NSInteger frameCount;
    NSData *sps;
    NSData *pps;
}

@property (nonatomic, strong) LMVideoStreamingConfiguration *configuration;
@property (nonatomic,weak) id<LMVideoEncodeDelegate> h264Delegate;
@property (nonatomic) BOOL isBackGround;

@end

@implementation LMHardwareVideoEncoder

#pragma mark -- LifeCycle
- (instancetype)initWithVideoStreamConfiguration:(LMVideoStreamingConfiguration *)configuration{
    if(self = [super init]){
        _configuration = configuration;
        [self initCompressionSession];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterBackground:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)initCompressionSession{
    if(compressionSession){
        VTCompressionSessionCompleteFrames(compressionSession, kCMTimeInvalid);
        
        VTCompressionSessionInvalidate(compressionSession);
        CFRelease(compressionSession);
        compressionSession = NULL;
    }
    
    OSStatus status = VTCompressionSessionCreate(NULL, _configuration.videoSize.width, _configuration.videoSize.height, kCMVideoCodecType_H264, NULL, NULL, NULL, VideoCompressonOutputCallback, (__bridge void *)self, &compressionSession);
    if(status != noErr){
        return;
    }
    
    /************************************视频会议客户端间视频交互*****************************************
     *手机视频硬编码上传视频数据到html5视频会议客户端,html5视频会议客户端显示不了手机上传的视频画面而详释.
     *为了html5视频会议客户端显示手机上传的视频画面，特选用BP-Baseline Profile且只支持CAVLC.BP-Baseline Profile选用CABAC导
     *致接收端马赛克严重.
     *
     *BP-Baseline Profile:基本画质.支持 I/P 帧,只支持无交错(Progressive)和CAVLC.
     *EP-Extended profile:进阶画质.支持 I/P/B/SP/SI 帧,只支持无交错(Progressive)和CAVLC.
     *MP-Main profile:主流画质.提供 I/P/B 帧,支持无交错(Progressive)和交错(Interlaced),也支持CAVLC和CABAC.
     *HP-High profile:高级画质.在main Profile的基础上增加了8x8内部预测、自定义量化、无损视频编码和更多的YUV格式.
     */
    
    status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_MaxKeyFrameInterval,(__bridge CFTypeRef)@(_configuration.videoMaxKeyframeInterval));
    status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,(__bridge CFTypeRef)@(_configuration.videoMaxKeyframeInterval));
    
    status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(_configuration.videoBitRate));
    NSArray *limit = @[@(_configuration.videoBitRate * 1.5/8),@(1)];
    status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limit);
    status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)@(_configuration.videoFrameRate));
    status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanFalse);
    //status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
    status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    //status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC);
    status = VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CAVLC);
    VTCompressionSessionPrepareToEncodeFrames(compressionSession);
    
}

- (void)setVideoBitRate:(NSUInteger)videoBitRate{
    VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(_configuration.videoBitRate));
    NSArray *limit = @[@(_configuration.videoBitRate * 1.5/8),@(1)];
    VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limit);
}

- (void)dealloc{
    if(compressionSession != NULL)
    {
        VTCompressionSessionCompleteFrames(compressionSession, kCMTimeInvalid);
        
        VTCompressionSessionInvalidate(compressionSession);
        CFRelease(compressionSession);
        compressionSession = NULL;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark -- LFVideoEncoder
- (void)encodeVideoData:(CVImageBufferRef)pixelBuffer timeStamp:(uint64_t)timeStamp{
    if(_isBackGround) return;
    
    frameCount ++;
    CMTime presentationTimeStamp = CMTimeMake(frameCount, 1000);
    VTEncodeInfoFlags flags;
    CMTime duration = CMTimeMake(1, (int32_t)_configuration.videoFrameRate);
    
    NSDictionary *properties = nil;
    if(frameCount % (int32_t)_configuration.videoMaxKeyframeInterval == 0){
        properties = @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES};
    }
    NSNumber *timeNumber = @(timeStamp);
    
    VTCompressionSessionEncodeFrame(compressionSession, pixelBuffer, presentationTimeStamp, duration, (__bridge CFDictionaryRef)properties, (__bridge_retained void *)timeNumber, &flags);
}

- (void)stopEncoder{
    VTCompressionSessionCompleteFrames(compressionSession, kCMTimeIndefinite);
}

- (void)setDelegate:(id<LMVideoEncodeDelegate>)delegate{
    _h264Delegate = delegate;
}

#pragma mark -- NSNotification
- (void)willEnterBackground:(NSNotification*)notification{
    _isBackGround = YES;
}

- (void)willEnterForeground:(NSNotification*)notification{
    [self initCompressionSession];
    _isBackGround = NO;
}

#pragma mark -- VideoCallBack
static void VideoCompressonOutputCallback(void *VTref, void *VTFrameRef, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer)
{
    if(!sampleBuffer) return;
    CFArrayRef array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    if(!array) return;
    CFDictionaryRef dic = (CFDictionaryRef)CFArrayGetValueAtIndex(array, 0);
    if(!dic) return;
    
    BOOL keyframe = !CFDictionaryContainsKey(dic, kCMSampleAttachmentKey_NotSync);
    uint64_t timeStamp = [((__bridge_transfer NSNumber*)VTFrameRef) longLongValue];
    
    LMHardwareVideoEncoder *videoEncoder = (__bridge LMHardwareVideoEncoder *)VTref;
    if(status != noErr){
        return;
    }
    
    if (keyframe && !videoEncoder->sps)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        if (statusCode == noErr)
        {
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr)
            {
                videoEncoder->sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                videoEncoder->pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
            }
        }
    }
    
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            // Read the NAL unit length
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData *videoFrameData = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            NSData *spsData = videoEncoder->sps;
            NSData *ppsData = videoEncoder->pps;
            NSDictionary *videoFrameDict = nil;
            if (videoFrameData || videoEncoder->sps || videoEncoder -> pps) {
                if (keyframe) {
                    /*
                     *C语言开内存空间
                     */
                    /*
                    unsigned char *body = NULL;
                    int iIndex = 0;
                    NSInteger bodyLength = 30241;
                    
                    const char *sps = (const char *)spsData.bytes;
                    NSInteger spsLength = spsData.length;
                    
                    const char *pps = (const char *)ppsData.bytes;
                    NSInteger ppsLength = ppsData.length;
                    
                    const char *videoData = (const char *)videoFrameData.bytes;
                    NSInteger videoDataLength = videoFrameData.length;
                    
                    body = (unsigned char *)malloc(bodyLength);
                    memset(body, 0, bodyLength);
                    
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x01;
                    memcpy(body + iIndex, sps, spsLength);
                    iIndex += spsLength;
                    
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x01;
                    memcpy(body + iIndex, pps, ppsLength);
                    iIndex +=  ppsLength;
                    
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x01;
                    memcpy(body + iIndex, videoData, videoDataLength);
                    iIndex += videoDataLength;
                    
                    NSData *currentData = [NSData dataWithBytes:body length:iIndex];
                    videoFrameDict = [NSDictionary dictionaryWithObjectsAndKeys:currentData, @"currentVideoData", [NSNumber numberWithInteger:iIndex], @"currentVideoDataLength", [NSNumber numberWithInteger:1], @"isVideoKeyFrame", nil];
                    free(body);
                    */
                    
                    const char headerBytes[] = "\x00\x00\x00\x01";
                    size_t headerBytesLength = sizeof(headerBytes) - 1;
                    NSData *headerBytesData = [NSData dataWithBytes:headerBytes length:headerBytesLength];
                    
                    NSMutableData *assemblyMutableData = [[NSMutableData alloc] init];
                    [assemblyMutableData appendData:headerBytesData];
                    [assemblyMutableData appendData:spsData];
                    [assemblyMutableData appendData:headerBytesData];
                    [assemblyMutableData appendData:ppsData];
                    [assemblyMutableData appendData:headerBytesData];
                    [assemblyMutableData appendData:videoFrameData];
                    NSData *assemblyData = [NSData dataWithData:assemblyMutableData];
                    
                    videoFrameDict = [NSDictionary dictionaryWithObjectsAndKeys:assemblyData, @"currentVideoData", [NSNumber numberWithInteger:assemblyData.length], @"currentVideoDataLength", [NSNumber numberWithInteger:1], @"isVideoKeyFrame", nil];
                    
                }
                else {
                    /*
                     *C语言开内存空间
                     */
                    /*
                    int iIndex = 0;
                    NSInteger videoLength = videoFrameData.length + 9;
                    unsigned char *body = (unsigned char *)malloc(videoLength);
                    memset(body, 0, videoLength);
                    
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x00;
                    body[iIndex ++] = 0x01;
                    
                    memcpy(body + iIndex, videoFrameData.bytes, videoFrameData.length);
                    iIndex += videoFrameData.length;
                    
                    NSData *currentData = [NSData dataWithBytes:body length:iIndex];
                    videoFrameDict = [NSDictionary dictionaryWithObjectsAndKeys:currentData, @"currentVideoData", [NSNumber numberWithInteger:iIndex], @"currentVideoDataLength", [NSNumber numberWithInteger:0], @"isVideoKeyFrame", nil];
                    free(body);
                    */
                    
                    const char headerBytes[] = "\x00\x00\x00\x01";
                    size_t headerBytesLength = sizeof(headerBytes) - 1;
                    NSData *headerBytesData = [NSData dataWithBytes:headerBytes length:headerBytesLength];
                    
                    NSMutableData *assemblyMutableData = [[NSMutableData alloc] init];
                    [assemblyMutableData appendData:headerBytesData];
                    [assemblyMutableData appendData:videoFrameData];
                    NSData *assemblyData = [NSData dataWithData:assemblyMutableData];
                    
                    videoFrameDict = [NSDictionary dictionaryWithObjectsAndKeys:assemblyData, @"currentVideoData", [NSNumber numberWithInteger:assemblyData.length], @"currentVideoDataLength", [NSNumber numberWithInteger:0], @"isVideoKeyFrame", nil];
                }
            }

//            LMVideoFrame *videoFrame = [LMVideoFrame new];
//            videoFrame.timestamp = timeStamp;
//            videoFrame.data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
//            videoFrame.isKeyFrame = keyframe;
//            videoFrame.sps = videoEncoder->sps;
//            videoFrame.pps = videoEncoder->pps;
//            
//            if(videoEncoder.h264Delegate && [videoEncoder.h264Delegate respondsToSelector:@selector(videoEncoder:videoFrame:)]) {
//                [videoEncoder.h264Delegate videoEncoder:videoEncoder videoFrame:videoFrame];
//            }
            
            if(videoEncoder.h264Delegate && [videoEncoder.h264Delegate respondsToSelector:@selector(videoEncoder:videoFrameDict:)]) {
                [videoEncoder.h264Delegate videoEncoder:videoEncoder videoFrameDict:videoFrameDict];
            }
            
            bufferOffset += AVCCHeaderLength + NALUnitLength;
            
        }
        
    }
}

@end
