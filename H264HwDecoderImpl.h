//
//  H264HwDecoderImpl.h
//  V5ConferenceiOSLib
//
//  Created by shenkun on 16/6/27.
//  Copyright © 2016年 guanjianchuang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVSampleBufferDisplayLayer.h>

@protocol H264HwDecoderImplDelegate <NSObject>

- (void)displayHwDecodedH264Frame:(CVImageBufferRef)imageBuffer;

@end

@interface H264HwDecoderImpl : NSObject

@property (weak, nonatomic) id<H264HwDecoderImplDelegate> delegate;

- (BOOL)initH264HwDecoder;
- (void)decodeH264Nalu:(uint8_t *)frame withSize:(uint32_t)frameSize;
- (void)deallocH264HwDecoder;

@end
