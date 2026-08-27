
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <substrate.h> 

#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"
static const int InsulationUnrestrictedPowerTarget = 65000;
static int gNotifyToken = -1;

// 🟢 手动声明 C 接口，彻底告别编译报错
typedef mach_port_t io_registry_entry_t;
extern "C" kern_return_t IORegistryEntrySetCFProperty(io_registry_entry_t entry, CFStringRef propertyName, CFTypeRef property);

// 👑 同步强读跨进程开关状态，0延迟
static NSInteger getRealTimeMitigationMode() {
    if (gNotifyToken == -1) {
        notify_register_check(NOTIFY_CPU_MODE, &gNotifyToken);
    }
    uint64_t state = 0;
    notify_get_state(gNotifyToken, &state);
    return (NSInteger)state;
}

// 👑 [绝杀机制]：C语言底层 IOKit 硬件拦截 (HoldCPU 纯正防反弹黑科技)
static kern_return_t (*orig_IORegistryEntrySetCFProperty)(io_registry_entry_t, CFStringRef, CFTypeRef);

static kern_return_t hook_IORegistryEntrySetCFProperty(io_registry_entry_t entry, CFStringRef propertyName, CFTypeRef property) {
    if (!propertyName) return orig_IORegistryEntrySetCFProperty(entry, propertyName, property);

    NSInteger mode = getRealTimeMitigationMode();
    
    if (mode == 1) { 
        // 模拟低频模式：拦截系统恢复频率的操作，死死按住 Level 2
        NSString *propStr = (__bridge NSString *)propertyName;
        if ([propStr isEqualToString:@"p-state-cap"] || [propStr isEqualToString:@"CPU_Ceiling"] || [propStr isEqualToString:@"CPU_Floor"]) {
            // 系统想满血？强制改为 Level 2 低频限制，并直接骗系统写入成功！
            orig_IORegistryEntrySetCFProperty(entry, propertyName, (__bridge CFTypeRef)@(2));
            return KERN_SUCCESS; 
        }
    } 
    else if (mode == 2) { 
        // 满血防降频模式：拦截降频操作，强写为无限制
        NSString *propStr = (__bridge NSString *)propertyName;
        if ([propStr isEqualToString:@"p-state-cap"] || [propStr isEqualToString:@"CPU_Ceiling"]) {
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

// 👑 [温控双保险]
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
    
    // 镇压苹果底层的两大护法：温控监控和硬件电源总控
    if ([processName isEqualToString:@"thermalmonitord"] || [processName isEqualToString:@"powerd"]) {
        
        %init;
        
        // 🚀 动态内存寻址 Hook，无视一切 SDK 报错！
        void *ioKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (ioKitHandle) {
            void *funcPtr = dlsym(ioKitHandle, "IORegistryEntrySetCFProperty");
            if (funcPtr) {
                MSHookFunction(funcPtr, (void *)hook_IORegistryEntrySetCFProperty, (void **)&orig_IORegistryEntrySetCFProperty);
            }
        }

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
