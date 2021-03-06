//
//  OOMStatisticsInfoCenter.m
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

#import "OOMStatisticsInfoCenter.h"
#import <mach/task.h>
#import <mach/mach.h>
#import <mach/mach_init.h>
#import <pthread.h>
#import <UIKit/UIkit.h>
#import "QQLeakDataUploadCenter.h"
#import "OOMDetectorLogger.h"
#import "MemoryIndicator.h"

#if __has_feature(objc_arc)
#error This file must be compiled without ARC. Use -fno-objc-arc flag.
#endif


static OOMStatisticsInfoCenter *center;

double overflow_limit;


@implementation CouMemoryStatusData


@end


@implementation CouCPUStatusData

+ (NSString *)usageKeyFrom:(NSString *)threadName threadId:(NSUInteger)threadId {
    return [NSString stringWithFormat:@"%@-%lu", threadName.length > 0? threadName : @"NoName", (unsigned long)threadId];
}

@end


@interface OOMStatisticsInfoCenter()
{
    double _singleLoginMaxMemory;
    NSTimeInterval _firstOOMTime;
    NSThread *_thread;
    NSTimer *_timer;
    BOOL _hasUpoad;
    MemoryIndicator *_indicatorView;
    double _residentMemSize;
}

@end

static mach_port_t main_thread_id;

@implementation OOMStatisticsInfoCenter

+ (void)load {
    main_thread_id = mach_thread_self();
}

#pragma -mark Implementation of interface
+ (mach_port_t)mainThreadMachID {
    return main_thread_id;
}

+(OOMStatisticsInfoCenter *)getInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        center = [OOMStatisticsInfoCenter new];
    });
    return center;
}

- (void)dealloc
{
    self.statisticsInfoBlock = nil;
    [super dealloc];
}

- (void)setStatisticsInfoBlock:(StatisticsInfoBlock)statisticsInfoBlock
{
    if (_statisticsInfoBlock != statisticsInfoBlock) {
        [_statisticsInfoBlock release];
        _statisticsInfoBlock = [statisticsInfoBlock copy];
    }
}

-(void)startMemoryOverFlowMonitor:(double)overFlowLimit
{
    [self uploadLastData];
    overflow_limit = overFlowLimit;
    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
    [_thread setName:@"MemoryOverflowMonitor"];
    _timer = [[NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(updateDeviceInfos) userInfo:nil repeats:YES] retain];
    [_thread start];
}

-(void)threadMain
{
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    [[NSRunLoop currentRunLoop] run];
    [_timer fire];
}
               

-(void)stopMemoryOverFlowMonitor
{
    [_timer invalidate];
    [_timer release];
    if(_thread){
        [_thread release];
    }
}


- (void)updateDeviceInfos {
    [self updateMemory];
    [self updateCPU];
}

-(void)updateMemory
{
    static int flag = 0;
    NSDictionary *memInfo = [self appMaxMemory];
    double resident_size_max = memInfo?[memInfo[@"resident_size_max"] doubleValue]:0;
    _residentMemSize = memInfo?[memInfo[@"resident_size"] doubleValue]:0;
    
    double physFootprintMemory = [self physFootprintMemory];
    
    if (self.statisticsInfoBlock) {
        self.statisticsInfoBlock(_residentMemSize);
    }
    __weak typeof(self)weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(self)strongSelf = weakSelf;
        CouMemoryStatusData *data = [CouMemoryStatusData new];
        data.phys_footprint = physFootprintMemory;
        data.resident_size = _residentMemSize;
        data.resident_size_max = resident_size_max;
        if (strongSelf.delegate && [strongSelf.delegate respondsToSelector:@selector(memStatusData:completionHandler:)]) {
            [strongSelf.delegate memStatusData:data completionHandler:^(BOOL result) {
                
            }];
        }
    });
    
    _indicatorView.memory = _residentMemSize;//physFootprintMemory;
//    NSLog(@"resident:%lfMb footprint:%lfMb",_residentMemSize, physFootprintMemory);
    ++flag;
    if(resident_size_max && flag >= 30){
        if(resident_size_max > _singleLoginMaxMemory){
            _singleLoginMaxMemory = resident_size_max;
            [self saveLastSingleLoginMaxMemory];
            flag = 0;
        }
    }
}


- (void)updateCPU {
    CouCPUStatusData *data = [self getTotolAndMainThreadUsage];
    __weak typeof(self)weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(self)strongSelf = weakSelf;
        if (strongSelf.delegate && [strongSelf.delegate respondsToSelector:@selector(CPUStatusData:completionHandler:)]) {
            [strongSelf.delegate CPUStatusData:data completionHandler:^(BOOL result) {
                
            }];
        }
    });
}

- (CouCPUStatusData *)getTotolAndMainThreadUsage {
    CouCPUStatusData *data = [CouCPUStatusData new];
    NSMutableDictionary *usages = [NSMutableDictionary dictionary];
    double mainThreadUsage = 0;
    double usageRatio = 0;
    thread_info_data_t thinfo;
    thread_act_array_t threads;
    thread_basic_info_t basic_info_t;
    mach_msg_type_number_t count = 0;
    mach_msg_type_number_t thread_info_count = THREAD_INFO_MAX;

    if (task_threads(mach_task_self(), &threads, &count) == KERN_SUCCESS) {
        for (int idx = 0; idx < count; idx++) {
            thread_t threadId = threads[idx];
            if (thread_info(threadId, THREAD_BASIC_INFO, (thread_info_t)thinfo, &thread_info_count) == KERN_SUCCESS) {
                basic_info_t = (thread_basic_info_t)thinfo;
                if (!(basic_info_t->flags & TH_FLAGS_IDLE)) {
                    double currentThreadUsage = basic_info_t->cpu_usage / (double)TH_USAGE_SCALE;
                    usageRatio += currentThreadUsage;
                    if (threadId == [[self class] mainThreadMachID]) {
                        mainThreadUsage = currentThreadUsage;
                    }
                    NSString *threadName = [self getThreadNameFromMachThread:threadId] ?: @"";
                    usages[threadName] = [NSNumber numberWithDouble:currentThreadUsage];
                }
            }
        }
        assert(vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(thread_t)) == KERN_SUCCESS);
    }
    data.totalUsage = usageRatio;
    data.mainThreadUsage = mainThreadUsage;
    data.usages = usages;
    return data;
}


- (NSString *)getThreadNameFromMachThread:(thread_t)threadId {
    if (threadId == [[self class] mainThreadMachID]) {
        return @"main";
    }
    
    pthread_t pt = pthread_from_mach_thread_np(threadId);
    char name[256];
    name[0] = '\0';
    pthread_getname_np(pt, name, sizeof name);
    return [CouCPUStatusData usageKeyFrom:[[NSString alloc] initWithUTF8String:name] threadId:threadId];
}


//触顶缓存逻辑
-(void)saveLastSingleLoginMaxMemory{
    if(_hasUpoad){
        NSString* currentMemory = [NSString stringWithFormat:@"%f", _singleLoginMaxMemory];
        NSString* overflowMemoryLimit =[NSString stringWithFormat:@"%f", overflow_limit];
        if(_singleLoginMaxMemory > overflow_limit){
            static BOOL isFirst = YES;
            if(isFirst){
                _firstOOMTime = [[NSDate date] timeIntervalSince1970];
                isFirst = NO;
            }
        }
        NSDictionary *minidumpdata = [NSDictionary dictionaryWithObjectsAndKeys:currentMemory,@"singleMemory",overflowMemoryLimit,@"threshold",[NSString stringWithFormat: @"%.2lf", _firstOOMTime],@"LaunchTime",nil];
        NSString *fileDir = [self singleLoginMaxMemoryDir];
        if (![[NSFileManager defaultManager] fileExistsAtPath:fileDir])
        {
            [[NSFileManager defaultManager] createDirectoryAtPath:fileDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *filePath = [fileDir stringByAppendingString:@"/apmLastMaxMemory.plist"];
        if(minidumpdata != nil){
            if([[NSFileManager defaultManager] fileExistsAtPath:filePath]){
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            }
            [minidumpdata writeToFile:filePath atomically:YES];
        }
    }

}


///  上传上次app运行中的内存信息。
-(void)uploadLastData
{
    __weak typeof(self)weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(self)strongSelf = weakSelf;
        NSString *filePath = [[self singleLoginMaxMemoryDir] stringByAppendingPathComponent:@"apmLastMaxMemory.plist"];
        NSDictionary *minidumpdata = [NSDictionary dictionaryWithContentsOfFile:filePath];
        _hasUpoad = YES;
        if([[NSFileManager defaultManager] fileExistsAtPath:filePath]){
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        }
        if(minidumpdata && [minidumpdata isKindOfClass:[NSDictionary class]])
        {
            NSString *memory = [minidumpdata objectForKey:@"singleMemory"];
            if(memory){
                NSDictionary *finalDic = [NSDictionary dictionaryWithObjectsAndKeys:minidumpdata,@"minidumpdata", nil];
                if (strongSelf.delegate && [strongSelf.delegate respondsToSelector:@selector(lastTimeAppMemData:completionHandler:)]) {
                    [strongSelf.delegate lastTimeAppMemData:finalDic completionHandler:^(BOOL) {
                        
                    }];
                }
            }
        }
    });
}

-(NSString*)singleLoginMaxMemoryDir
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *LibDirectory = [paths objectAtIndex:0];
    NSString *path = [LibDirectory stringByAppendingPathComponent:@"/Caches/Memory"];
    return path;
}

- (NSDictionary *)appMaxMemory
{
    mach_task_basic_info_data_t taskInfo;
    unsigned infoCount = sizeof(taskInfo);
    kern_return_t kernReturn = task_info(mach_task_self(),
                                         MACH_TASK_BASIC_INFO,
                                         (task_info_t)&taskInfo,
                                         &infoCount);
    
    if (kernReturn != KERN_SUCCESS
        ) {
        return nil;
    }
    
    NSDictionary *info = @{
        @"resident_size":@(taskInfo.resident_size / 1024.0 / 1024.0),
        @"resident_size_max":@(taskInfo.resident_size_max / 1024.0 / 1024.0)
    };
    return info;
}

- (double)physFootprintMemory{
    int64_t memoryUsageInByte = 0;
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t kernelReturn = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t) &vmInfo, &count);
    if(kernelReturn == KERN_SUCCESS) {
        memoryUsageInByte = (int64_t) vmInfo.phys_footprint;
    }
    return (double)memoryUsageInByte/ 1024.0 / 1024.0;
}


- (void)showMemoryIndicatorView:(BOOL)yn
{
    if (yn) {
        if (!_indicatorView) {
            _indicatorView = [MemoryIndicator indicator];
        }
        [_indicatorView setThreshhold:overflow_limit];
    }
    [_indicatorView show:yn];
}

- (void)setupMemoryIndicatorFrame:(CGRect)frame
{
    if (!_indicatorView) {
        [self showMemoryIndicatorView:YES];
    }
    _indicatorView.frame = frame;
}

@end
