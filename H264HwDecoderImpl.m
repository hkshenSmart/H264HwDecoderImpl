//
//  H264HwDecoderImpl.m
//  V5ConferenceiOSLib
//
//  Created by shenkun on 16/6/27.
//  Copyright © 2016年 guanjianchuang. All rights reserved.
//

#import "H264HwDecoderImpl.h"

#define h264outputWidth 800
#define h264outputHeight 600

@interface H264HwDecoderImpl() {
    uint8_t *sps;
    NSInteger spsSize;
    uint8_t *pps;
    NSInteger ppsSize;
    VTDecompressionSessionRef decompressionSession;
    CMVideoFormatDescriptionRef videoFormatDescription;
}

@property (nonatomic, assign) BOOL isH264HwDecodeFailed;

@end

@implementation H264HwDecoderImpl

//硬解码回调函数
static void didDecompress(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration) {
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
    H264HwDecoderImpl *decoder = (__bridge H264HwDecoderImpl *)decompressionOutputRefCon;
    
    if (decoder.delegate != nil) {
        [decoder.delegate displayHwDecodedH264Frame:pixelBuffer];
    }
}


- (BOOL)initH264HwDecoder {
    if (decompressionSession) {
        return YES;
    }
    
    const uint8_t *const parameterSetPointers[2] = {sps, pps};
    const size_t parameterSetSizes[2] = {spsSize, ppsSize};
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //param count
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal start code size
                                                                          &videoFormatDescription);
    
    if (status == noErr) {
        NSDictionary *destinationPixelBufferAttributes = @{
                                                           (id)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
                                                           //硬解码必须是 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                                                           //或者是kCVPixelFormatType_420YpCbCr8Planar
                                                           //因为iOS是nv12,其他是nv21
                                                           (id)kCVPixelBufferWidthKey:[NSNumber numberWithInt:h264outputHeight * 2],
                                                           (id)kCVPixelBufferHeightKey:[NSNumber numberWithInt:h264outputWidth * 2],
                                                           //这里宽高和编码反的
                                                           (id)kCVPixelBufferOpenGLCompatibilityKey:[NSNumber numberWithBool:YES]
                                                           };
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              videoFormatDescription,
                                              NULL,
                                              (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                              &callBackRecord,
                                              &decompressionSession);
        VTSessionSetProperty(decompressionSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
        VTSessionSetProperty(decompressionSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
        
    } else {
        NSLog(@"iOS8VT:CMVideoFormatDescriptionCreateFromH264ParameterSets failed status = %d", (int)status);
        return NO;
    }
    
    return YES;
}

- (CVPixelBufferRef)decode:(uint8_t *)frame withSize:(uint32_t)frameSize {
    
    CVPixelBufferRef outputPixelBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL,
                                                          (void *)frame,
                                                          frameSize,
                                                          kCFAllocatorNull,
                                                          NULL,
                                                          0,
                                                          frameSize,
                                                          FALSE,
                                                          &blockBuffer);
    if (status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {frameSize};
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           videoFormatDescription ,
                                           1, 0, NULL, 1, sampleSizeArray,
                                           &sampleBuffer);
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(decompressionSession,
                                                                      sampleBuffer,
                                                                      flags,
                                                                      &outputPixelBuffer,
                                                                      &flagOut);

            if (decodeStatus == kVTInvalidSessionErr) {
                NSLog(@"iOS8VT:invalid session, reset decoder session");
                
            } else if (decodeStatus == kVTVideoDecoderBadDataErr) {
                NSLog(@"iOS8VT:decode failed status = %d (Bad data)", (int)decodeStatus);
                
                _isH264HwDecodeFailed = YES;
                
            } else if (decodeStatus != noErr) {
                NSLog(@"iOS8VT:decode failed status = %d", (int)decodeStatus);
                
                _isH264HwDecodeFailed = YES;
            }
            CFRelease(sampleBuffer);
        }
        CFRelease(blockBuffer);
    }
    
    return outputPixelBuffer;
}

//另外一种解码显示方式
- (CVPixelBufferRef)decode:(uint8_t *)frame withSize:(uint32_t)frameSize withShowLayer:(AVSampleBufferDisplayLayer *)videoLayer {
    
    CVPixelBufferRef outputPixelBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL,
                                                         (void *)frame,
                                                         frameSize,
                                                         kCFAllocatorNull,
                                                         NULL,
                                                         0,
                                                         frameSize,
                                                         FALSE,
                                                         &blockBuffer);
    if (status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        
        status = CMSampleBufferCreate(kCFAllocatorDefault,
                                      blockBuffer,
                                      true, NULL,
                                      NULL, videoFormatDescription, 1, 0,
                                      NULL, 0, NULL,
                                      &sampleBuffer);
        
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_IsDependedOnByOthers, kCFBooleanTrue);
        
        int nalu_type = (frame[4] & 0x1F);
        if (nalu_type == 1) {
            //P-frame
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_DependsOnOthers, kCFBooleanTrue);
        } else {
            //I-frame
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_NotSync, kCFBooleanFalse);
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_DependsOnOthers, kCFBooleanFalse);
        }
        
        if (status == kCMBlockBufferNoErr) {
            if ([videoLayer isReadyForMoreMediaData]) {
                dispatch_sync(dispatch_get_main_queue(),^{
                    [videoLayer enqueueSampleBuffer:sampleBuffer];
                });
            }
            
            CFRelease(sampleBuffer);
        }
        
        CFRelease(blockBuffer);
    }
    
    return outputPixelBuffer;
}

- (void)decodeH264Nalu:(uint8_t *)frame withSize:(uint32_t)frameSize {
    //NSLog(@"------decode");
    int nalu_type = (frame[4] & 0x1F);
    CVPixelBufferRef pixelBuffer = NULL;
    //uint32_t nalSize = (uint32_t)(frameSize - 4);
    //uint8_t *pNalSize = (uint8_t *)(&nalSize);
    //frame[0] = *(pNalSize + 3);
    //frame[1] = *(pNalSize + 2);
    //frame[2] = *(pNalSize + 1);
    //frame[3] = *(pNalSize);
    
    uint32_t big = NSSwapHostIntToBig(frameSize - 4);
    memcpy(frame, &big, 4);
    
    //关键帧丢数据则绿屏,B/P丢数据会卡顿
    switch (nalu_type) {
        case 0x05: {
            //NSLog(@"i frame");
            if([self initH264HwDecoder]) {
                pixelBuffer = [self decode:frame withSize:frameSize];
                _isH264HwDecodeFailed = NO;
            }
            break;
        }
        case 0x06: {
            //NSLog(@"SEI");
            break;
        }
        case 0x07: {
            //NSLog(@"SPS");
            spsSize = frameSize - 4;
            sps = malloc(spsSize);
            memcpy(sps, &frame[4], spsSize);
            break;
        }
        case 0x08: {
            //NSLog(@"PPS");
            ppsSize = frameSize - 4;
            pps = malloc(ppsSize);
            memcpy(pps, &frame[4], ppsSize);
            break;
        }
        default: {
           //NSLog(@"B/P frame");
           if([self initH264HwDecoder]) {
               if (!_isH264HwDecodeFailed) {
                   pixelBuffer = [self decode:frame withSize:frameSize];
               }
               //pixelBuffer = [self decode:frame withSize:frameSize];
            }
            break;
        }
    }
}

- (void)deallocH264HwDecoder {
    
    if (decompressionSession) {
        VTDecompressionSessionInvalidate(decompressionSession);
        CFRelease(decompressionSession);
        decompressionSession = NULL;
    }
    
    if(videoFormatDescription) {
        CFRelease(videoFormatDescription);
        videoFormatDescription = NULL;
    }
    
    free(sps);
    free(pps);
    spsSize = ppsSize = 0;
    _isH264HwDecodeFailed = NO;
}

@end
