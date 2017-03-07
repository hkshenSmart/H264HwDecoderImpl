//
//  LMHardwareVideoEncoder.h
//  V5ConferenceiOSLib
//
//  Created by shenkun on 16/6/16.
//  Copyright © 2016年 guanjianchuang. All rights reserved.
//

#import "LMVideoEncoder.h"

@interface LMHardwareVideoEncoder : NSObject<LMVideoEncoder>

#pragma mark - Initializer
///=============================================================================
/// @name Initializer
///=============================================================================
- (nullable instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (nullable instancetype)new UNAVAILABLE_ATTRIBUTE;

@end
