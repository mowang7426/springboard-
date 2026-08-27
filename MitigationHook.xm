
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <IOKit/IOKitLib.h>
#import <substrate.h> // 必须引入，支持 MSHookFunction 拦截 C 语言函数

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"
static const int InsulationUnrestrictedPowerTarget = 65000;
static int gNotifyToken = -1;

// 👑 [绝杀机制 1]：同步无延迟强读内核通信状态
static NSInteger getRealTimeMitigationMode() {
    if (gNotifyToken == -1) {
        notify_register_check(NOTIFY_CPU_MODE, &gNotifyToken);
    }
    uint64_t state = 0;
    notify_get_state(gNotifyToken, &state);
    return (NSInteger)state;
}

// 👑 [绝杀机制 2]：C语言底层 IOKit 硬件拦截 (HoldCPU 同款防反弹黑科技)
static kern_return_t (*orig_IORegistryEntrySetCFProperty)(io_registry_entry_t entry, CFStringRef propertyName, CFTypeRef property);

static kern_return_t hook_IORegistryEntrySetCFProperty(io_registry_entry_t entry, CFStringRef propertyName, CFTypeRef property) {
    if (!propertyName) return orig_IORegistryEntrySetCFProperty(entry, propertyName, property);

    NSInteger mode = getRealTimeMitigationMode();
    
    if (mode == 1) { 
        // 模拟低频模式：拦截系统试图恢复频率的操作，死死按住 Level 2
        if (CFStringCompare(propertyName, CFSTR("p-state-cap"), 0) == kCFCompareEqualTo ||
            CFStringCompare(propertyName, CFSTR("CPU_Ceiling"), 0) == kCFCompareEqualTo ||
            CFStringCompare(propertyName, CFSTR("CPU_Floor"), 0) == kCFCompareEqualTo) {
            // 系统想满血？强制改为 Level 2 低频限制，并直接骗系统写入成功！
            orig_IORegistryEntrySetCFProperty(entry, propertyName, (__bridge CFTypeRef)@(2));
            return KERN_SUCCESS; 
        }
    } 
    else if (mode == 2) { 
        // 满血防降频模式：拦截降频操作，强写为无限制
        if (CFStringCompare(propertyName, CFSTR("p-state-cap"), 0) == kCFCompareEqualTo ||
            CFStringCompare(propertyName, CFSTR("CPU_Ceiling"), 0) == kCFCompareEqualTo) {
            orig_IORegistryEntrySetCFProperty(entry, propertyName, (__bridge CFTypeRef)@(15));
            return KERN_SUCCESS; 
        }
    }

    return orig_IORegistryEntrySetCFProperty(entry, propertyName, property);
}

@interface MitigationController : NSObject
- (void)setPowerSaveActive:(BOOL)active;
- (void)setCPULevel:(int)level;
- (void)setCPULowPowerTarget:(int)power;
- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source;
- (void)setCPUPowerZoneTarget:(int)power;
- (void)updateCPU;
@end

// 👑 [绝杀机制 3]：温控系统逻辑层拦截双保险
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
    if (mode == 1) {
        [self setPowerSaveActive:YES];
        [self setCPULevel:2];
    } else if (mode == 2) {
        [self setPowerSaveActive:NO];
        [self setCPULevel:0];
    }
    %orig;
}

%end

%ctor {
    NSString *processName = [NSProcessInfo processInfo].processName;
    
    // 同时镇压苹果底层的两大护法：温控监控 (thermalmonitord) 和 硬件电源总控 (powerd)
    if ([processName isEqualToString:@"thermalmonitord"] || [processName isEqualToString:@"powerd"]) {
        
        %init;
        
        // 🚀 启动 IOKit C 语言级拦截，这一步是彻底锁死硬件的核心！
        MSHookFunction((void *)IORegistryEntrySetCFProperty, (void *)hook_IORegistryEntrySetCFProperty, (void **)&orig_IORegistryEntrySetCFProperty);

        // 底层高优先级守护定时器：强行持续心跳压制
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), 1.0 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            NSInteger mode = getRealTimeMitigationMode();
            if (mode != 0) {
                Class cls = objc_getClass("MitigationController");
                if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
                    id controller = [cls performSelector:@selector(sharedInstance)];
                    if (controller && [controller respondsToSelector:@selector(updateCPU)]) {
                        [controller performSelector:@selector(updateCPU)];
                    }
                }
            }
        });
        dispatch_resume(timer);
    }
}
