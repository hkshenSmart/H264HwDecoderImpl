//
//  LMVideoEncoder.h
//  V5ConferenceiOSLib
//
//  Created by shenkun on 16/6/16.
//  Copyright © 2016年 guanjianchuang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LMVideoStreamingConfiguration.h"

@protocol LMVideoEncoder;
/// 编码器编码后回调
@protocol LMVideoEncodeDelegate <NSObject>
@required
//- (void)videoEncoder:(nullable id<LMVideoEncoder>)encoder videoFrame:(nullable LMVideoFrame*)frame;
- (void)videoEncoder:(nullable id<LMVideoEncoder>)encoder videoFrameDict:(nullable NSDictionary *)frameDict;
@end

/// 编码器抽象的接口
@protocol LMVideoEncoder <NSObject>
@required
- (void)encodeVideoData:(nullable CVImageBufferRef)pixelBuffer timeStamp:(uint64_t)timeStamp;
- (void)stopEncoder;
- (void)setVideoBitRate:(NSUInteger)videoBitRate;
@optional
- (nullable instancetype)initWithVideoStreamConfiguration:(nullable LMVideoStreamingConfiguration*)configuration;
- (void)setDelegate:(nullable id<LMVideoEncodeDelegate>)delegate;
@end

