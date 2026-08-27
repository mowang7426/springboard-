
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <IOKit/IOKitLib.h>

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"

static NSInteger insulationCpuMode = 0;
static const int InsulationUnrestrictedPowerTarget = 65000;

@interface MitigationController : NSObject
- (void)setPowerSaveActive:(BOOL)active;
- (void)setCPULevel:(int)level;
- (void)setCPULowPowerTarget:(int)power;
- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source;
- (void)setCPUPowerZoneTarget:(int)power;
@end

// =====================================================================
// 👑 [核弹级黑科技] C 函数直接 Hook (HoldCPU 同款内核穿透拦截)
// 无论苹果系统怎么想改频率，只要经过这里，全部被篡改！
// =====================================================================

%hookf(kern_return_t, IORegistryEntrySetCFProperty, io_registry_entry_t entry, CFStringRef propertyName, CFTypeRef property) {
    if (!propertyName) return %orig(entry, propertyName, property);

    if (insulationCpuMode == 1) {
        // 【模拟低频模式】拦截系统试图恢复频率的操作，强行丢进垃圾桶并锁死 Level 2
        if (CFStringCompare(propertyName, CFSTR("p-state-cap"), 0) == kCFCompareEqualTo ||
            CFStringCompare(propertyName, CFSTR("CPU_Ceiling"), 0) == kCFCompareEqualTo ||
            CFStringCompare(propertyName, CFSTR("CPU_Floor"), 0) == kCFCompareEqualTo) {
            return %orig(entry, propertyName, (__bridge CFTypeRef)@(2));
        }
    } 
    else if (insulationCpuMode == 2) {
        // 【满血防降频模式】拦截系统试图降频的操作，强行置为满血 Level 15 (或 0)
        if (CFStringCompare(propertyName, CFSTR("p-state-cap"), 0) == kCFCompareEqualTo ||
            CFStringCompare(propertyName, CFSTR("CPU_Ceiling"), 0) == kCFCompareEqualTo) {
            return %orig(entry, propertyName, (__bridge CFTypeRef)@(15));
        }
    }
    
    return %orig(entry, propertyName, property);
}

// =====================================================================
// 常规 Controller 拦截 (双保险)
// =====================================================================

%hook MitigationController

- (void)setPowerSaveActive:(BOOL)active {
    if (insulationCpuMode == 1) { %orig(YES); return; }
    if (insulationCpuMode == 2) { %orig(NO); return; }
    %orig(active);
}

- (void)setCPULevel:(int)level {
    if (insulationCpuMode == 1) { %orig(2); return; }
    if (insulationCpuMode == 2) { %orig(0); return; }
    %orig(level);
}

- (void)setCPULowPowerTarget:(int)power {
    if (insulationCpuMode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget)); return; }
    %orig(power);
}

- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source {
    if (insulationCpuMode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget), source); return; }
    %orig(power, source);
}

- (void)setCPUPowerZoneTarget:(int)power {
    if (insulationCpuMode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget)); return; }
    %orig(power);
}

%end

// =====================================================================
// 初始化与进程注入
// =====================================================================

%ctor {
    // ⚠️ 我们这次同时注入了 thermalmonitord 和 powerd
    NSString *processName = [NSProcessInfo processInfo].processName;
    if (![processName isEqualToString:@"thermalmonitord"] && ![processName isEqualToString:@"powerd"]) {
        return;
    }

    %init;

    // 监听来自桌面的模式切换指令
    int token;
    notify_register_dispatch(NOTIFY_CPU_MODE, &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        if (notify_get_state(t, &state) == NOTIFY_STATUS_OK) {
            insulationCpuMode = (NSInteger)state;
            
            // 收到指令后，主动触发一次底层刷新，让 Hook 瞬间生效
            Class cls = objc_getClass("MitigationController");
            if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
                id controller = [cls performSelector:@selector(sharedInstance)];
                if (controller && [controller respondsToSelector:@selector(updateCPU)]) {
                    [controller performSelector:@selector(updateCPU)];
                }
            }
        }
    });

    uint64_t initialState = 0;
    if (notify_get_state(token, &initialState) == NOTIFY_STATUS_OK) {
        insulationCpuMode = (NSInteger)initialState;
    }
}

