
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <substrate.h> 
#import <CoreFoundation/CoreFoundation.h>

#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"
static const int InsulationUnrestrictedPowerTarget = 65000;
static int gNotifyToken = -1;

@interface NSObject (SBCPUMitigationDummy)
+ (id)sharedInstance;
- (void)updateCPU;
@end

typedef mach_port_t io_registry_entry_t;
extern "C" kern_return_t IORegistryEntrySetCFProperty(io_registry_entry_t entry, CFStringRef propertyName, CFTypeRef property);

static uint64_t getRealTimeState() {
    if (gNotifyToken == -1) {
        notify_register_check(NOTIFY_CPU_MODE, &gNotifyToken);
    }
    uint64_t state = 0;
    notify_get_state(gNotifyToken, &state);
    return state;
}

static NSInteger getRealTimeMitigationMode() { return getRealTimeState() & 0xFF; }
static BOOL getRealTimeBlockDimming() { return (getRealTimeState() >> 8) & 1; }
static BOOL getRealTimeForceFastCharge() { return (getRealTimeState() >> 9) & 1; }

// 👑 [绝杀机制]：C语言底层 IOKit 硬件拦截中心
static kern_return_t (*orig_IORegistryEntrySetCFProperty)(io_registry_entry_t, CFStringRef, CFTypeRef);

static kern_return_t hook_IORegistryEntrySetCFProperty(io_registry_entry_t entry, CFStringRef propertyName, CFTypeRef property) {
    if (!propertyName) return orig_IORegistryEntrySetCFProperty(entry, propertyName, property);

    NSInteger mode = getRealTimeMitigationMode();
    BOOL blockDimming = getRealTimeBlockDimming();
    BOOL forceFastCharge = getRealTimeForceFastCharge();
    NSString *propStr = (__bridge NSString *)propertyName;
    NSString *lowerPropStr = propStr.lowercaseString;
    
    // 🟢 [BUG 5 Fix] 防止暗屏硬件底层拦截，兼容 iOS 14 - 17 所有的底层节点
    if (blockDimming) {
        if ([lowerPropStr isEqualToString:@"max-brightness"] ||
            [lowerPropStr isEqualToString:@"brightness-limit"] ||
            [lowerPropStr isEqualToString:@"iomfb_brightness_limit"] ||
            [lowerPropStr containsString:@"thermalmitigation"] ||
            [lowerPropStr containsString:@"thermallimit"] ||
            [lowerPropStr containsString:@"mitigation"]) {
            return KERN_SUCCESS; // 直接假装成功，绝对不执行暗屏动作
        }
    }

    // 🚀 [突破 70% 优化充电] 粉碎系统偷切的降速
    if (forceFastCharge) {
        if ([lowerPropStr containsString:@"chargecurrent"] ||
            [lowerPropStr containsString:@"chargelimit"] ||
            [lowerPropStr containsString:@"maxcharge"] ||
            [lowerPropStr containsString:@"chargerate"]) {
            // 无论系统下发什么，直接死锁写入 5A/5000mA (5000 毫安时)
            orig_IORegistryEntrySetCFProperty(entry, propertyName, (__bridge CFTypeRef)@(5000));
            return KERN_SUCCESS;
        }
        
        if ([lowerPropStr containsString:@"chargeinhibit"] || [lowerPropStr containsString:@"smartcharge"]) {
            // 拒绝系统对电池“优化充电”从而导致断流的休眠指令
            orig_IORegistryEntrySetCFProperty(entry, propertyName, kCFBooleanFalse);
            return KERN_SUCCESS;
        }
    }

    // 核心 CPU 降温
    if (mode == 1) { 
        if ([propStr isEqualToString:@"p-state-cap"] || [propStr isEqualToString:@"CPU_Ceiling"] || [propStr isEqualToString:@"CPU_Floor"]) {
            orig_IORegistryEntrySetCFProperty(entry, propertyName, (__bridge CFTypeRef)@(2)); return KERN_SUCCESS; 
        }
    } 
    else if (mode == 2) { 
        if ([propStr isEqualToString:@"p-state-cap"] || [propStr isEqualToString:@"CPU_Ceiling"]) {
            orig_IORegistryEntrySetCFProperty(entry, propertyName, (__bridge CFTypeRef)@(15)); return KERN_SUCCESS; 
        }
    }

    return orig_IORegistryEntrySetCFProperty(entry, propertyName, property);
}

%hook MitigationController
- (void)setPowerSaveActive:(BOOL)active {
    NSInteger mode = getRealTimeMitigationMode();
    if (mode == 1) { %orig(YES); return; }
    if (mode == 2) { %orig(NO); return; }
    %orig(active);
}
- (void)setCPULevel:(int)level {
    NSInteger mode = getRealTimeMitigationMode();
    if (mode == 1) { %orig(2); return; }
    if (mode == 2) { %orig(0); return; }
    %orig(level);
}
- (void)setCPULowPowerTarget:(int)power {
    NSInteger mode = getRealTimeMitigationMode();
    if (mode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget)); return; }
    %orig(power);
}
- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source {
    NSInteger mode = getRealTimeMitigationMode();
    if (mode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget), source); return; }
    %orig(power, source);
}
- (void)setCPUPowerZoneTarget:(int)power {
    NSInteger mode = getRealTimeMitigationMode();
    if (mode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget)); return; }
    %orig(power);
}
- (void)updateCPU {
    NSInteger mode = getRealTimeMitigationMode();
    if (mode == 1) { [self setPowerSaveActive:YES]; [self setCPULevel:2]; } 
    else if (mode == 2) { [self setPowerSaveActive:NO]; [self setCPULevel:0]; }
    %orig;
}
%end

%ctor {
    NSString *processName = [NSProcessInfo processInfo].processName;
    if ([processName isEqualToString:@"thermalmonitord"] || [processName isEqualToString:@"powerd"]) {
        %init;
        void *ioKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (ioKitHandle) {
            void *funcPtr = dlsym(ioKitHandle, "IORegistryEntrySetCFProperty");
            if (funcPtr) MSHookFunction(funcPtr, (void *)hook_IORegistryEntrySetCFProperty, (void **)&orig_IORegistryEntrySetCFProperty);
        }

        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), 1.0 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            NSInteger mode = getRealTimeMitigationMode();
            if (mode != 0) {
                id cls = (id)objc_getClass("MitigationController");
                if (cls) {
                    id controller = [cls sharedInstance];
                    if (controller && [controller respondsToSelector:@selector(updateCPU)]) {
                        [controller updateCPU];
                    }
                }
            }
        });
        dispatch_resume(timer);
    }
}

