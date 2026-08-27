
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <IOKit/IOKitLib.h>
#import <substrate.h> // 必须引入，用于 MSHookFunction

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"

static NSInteger insulationCpuMode = 0;
static const int InsulationUnrestrictedPowerTarget = 65000;

@interface MitigationController : NSObject
- (void)setPowerSaveActive:(BOOL)active;
- (void)setCPULevel:(int)level;
- (void)updateCPU;
@end

// =====================================================================
// 👑 [核心黑科技] IOKit 底层 C 函数拦截 (HoldCPU 同款机制)
// =====================================================================

// 保存原函数的指针
static kern_return_t (*orig_IORegistryEntrySetCFProperty)(io_registry_entry_t entry, CFStringRef propertyName, CFTypeRef property);

// 我们的拦截函数
static kern_return_t hook_IORegistryEntrySetCFProperty(io_registry_entry_t entry, CFStringRef propertyName, CFTypeRef property) {
    if (insulationCpuMode == 1) {
        // 【模拟低频模式】拦截系统试图恢复频率的操作
        if (CFStringCompare(propertyName, CFSTR("p-state-cap"), 0) == kCFCompareEqualTo ||
            CFStringCompare(propertyName, CFSTR("CPU_Ceiling"), 0) == kCFCompareEqualTo ||
            CFStringCompare(propertyName, CFSTR("CPU_Floor"), 0) == kCFCompareEqualTo) {
            
            // 系统想乱改？不准！我们强行把写入的值替换成极低频限制 (Level 2)
            orig_IORegistryEntrySetCFProperty(entry, propertyName, (__bridge CFTypeRef)@(2));
            
            // 返回成功，欺骗苹果系统，让它以为自己成功了
            return KERN_SUCCESS; 
        }
    } 
    else if (insulationCpuMode == 2) {
        // 【防降频满血模式】拦截系统试图降低频率的操作
        if (CFStringCompare(propertyName, CFSTR("p-state-cap"), 0) == kCFCompareEqualTo ||
            CFStringCompare(propertyName, CFSTR("CPU_Ceiling"), 0) == kCFCompareEqualTo) {
            
            // 强行把写入的值替换成满血无限制 (Level 15/0)
            orig_IORegistryEntrySetCFProperty(entry, propertyName, (__bridge CFTypeRef)@(15));
            return KERN_SUCCESS; 
        }
    }

    // 其他不相关的属性，放行给系统正常处理
    return orig_IORegistryEntrySetCFProperty(entry, propertyName, property);
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
    NSString *processName = [NSProcessInfo processInfo].processName;
    if (![processName isEqualToString:@"thermalmonitord"]) return;

    %init;

    // 🚀 [黑科技生效] Hook 底层 C 语言写入函数
    MSHookFunction((void *)IORegistryEntrySetCFProperty, (void *)hook_IORegistryEntrySetCFProperty, (void **)&orig_IORegistryEntrySetCFProperty);

    // 监听来自桌面的模式切换指令
    int token;
    notify_register_dispatch(NOTIFY_CPU_MODE, &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        if (notify_get_state(t, &state) == NOTIFY_STATUS_OK) {
            insulationCpuMode = (NSInteger)state;
            
            // 收到指令后，主动触发一次底层刷新，立刻让 Hook 拦截生效
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
