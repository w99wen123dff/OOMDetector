//
//  OOMStatisticsInfoCenter.h
//  QQLeak
//
//  Tencent is pleased to support the open source community by making OOMDetector available.
//  Copyright (C) 2017 THL A29 Limited, a Tencent company. All rights reserved.
//  Licensed under the MIT License (the "License"); you may not use this file except
//  in compliance with the License. You may obtain a copy of the License at
//
//  http://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
//

#ifndef OOMStaticsInfoCenter_h
#define OOMStaticsInfoCenter_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void (^StatisticsInfoBlock)(NSInteger memorySize_M);

@interface CouMemoryStatusData : NSObject
@property (nonatomic, assign) double phys_footprint;
@property (nonatomic, assign) double resident_size;
@property (nonatomic, assign) double resident_size_max;
@end


@interface CouCPUStatusData : NSObject
@property (nonatomic, assign) double mainThreadUsage;
@property (nonatomic, assign) double totalUsage;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *usages;

+ (NSString *)usageKeyFrom:(NSString *)threadName threadId:(NSUInteger)threadId;

@end



@protocol CouOOMPerformanceDataDelegate <NSObject>

/*! @brief 前一次app运行时单次生命周期内的最大物理内存数据
*  @param data 性能数据
*/
-(void)lastTimeAppMemData:(NSDictionary *)data completionHandler:(void (^)(BOOL))completionHandler;


-(void)memStatusData:(CouMemoryStatusData *)data completionHandler:(void (^)(BOOL))completionHandler;


-(void)CPUStatusData:(CouCPUStatusData *)data completionHandler:(void (^)(BOOL))completionHandler;

@end



@interface OOMStatisticsInfoCenter : NSObject

@property (nonatomic, copy) StatisticsInfoBlock statisticsInfoBlock;

@property (nonatomic, assign) id<CouOOMPerformanceDataDelegate> delegate;

+(OOMStatisticsInfoCenter *)getInstance;

-(void)startMemoryOverFlowMonitor:(double)overFlowLimit;

-(void)stopMemoryOverFlowMonitor;

- (void)showMemoryIndicatorView:(BOOL)yn;

- (void)setupMemoryIndicatorFrame:(CGRect)frame;

-(void)updateMemory;

- (void)updateCPU;
@end

#endif /* OOMStaticsInfoCenter_h */
