
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>

#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"
static const int InsulationUnrestrictedPowerTarget = 65000;
static int gNotifyToken = -1;

@interface MitigationController : NSObject
- (void)setPowerSaveActive:(BOOL)active;
- (void)setCPULevel:(int)level;
- (void)setCPULowPowerTarget:(int)power;
- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source;
- (void)setCPUPowerZoneTarget:(int)power;
- (void)updateCPU;
@end

// 👑 [最关键修复] 同步强读内核状态，彻底解决主线程死锁导致的指令丢失！
static NSInteger getRealTimeMitigationMode() {
    if (gNotifyToken == -1) {
        notify_register_check(NOTIFY_CPU_MODE, &gNotifyToken);
    }
    uint64_t state = 0;
    notify_get_state(gNotifyToken, &state);
    return (NSInteger)state;
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
    // 强制锁死 Level 2 (苹果官方底层的降频档位)，绝不脱锁！
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
    if (![processName isEqualToString:@"thermalmonitord"]) return;

    %init;

    // 🚀 死守反击定时器：放入底层 Global Queue，绝对不被卡死！
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

