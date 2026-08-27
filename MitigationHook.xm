
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>

#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"

static NSInteger insulationCpuMode = 0;
static const int InsulationUnrestrictedPowerTarget = 65000;
static id g_activeMitigationController = nil;

@interface MitigationController : NSObject
- (void)setPowerSaveActive:(BOOL)active;
- (void)setCPULevel:(int)level;
- (void)setCPULowPowerTarget:(int)power;
- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source;
- (void)setCPUPowerZoneTarget:(int)power;
- (void)updateCPU;
@end

// 🟢 每秒死循环暴力镇压，绝不给系统恢复的机会
static void enforceMitigationState(void) {
    if (!g_activeMitigationController) return;
    @try {
        if (insulationCpuMode == 1) { 
            // 模拟低电模式：强行打入 Level 2
            if ([g_activeMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) {
                [g_activeMitigationController setPowerSaveActive:YES];
            }
            if ([g_activeMitigationController respondsToSelector:@selector(setCPULevel:)]) {
                [g_activeMitigationController setCPULevel:2];
            }
        } else if (insulationCpuMode == 2) {
            // 满血模式：强行解除
            if ([g_activeMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) {
                [g_activeMitigationController setPowerSaveActive:NO];
            }
            if ([g_activeMitigationController respondsToSelector:@selector(setCPULevel:)]) {
                [g_activeMitigationController setCPULevel:0];
            }
        }
    } @catch (NSException *e) {}
}

%hook MitigationController

- (instancetype)init {
    id orig = %orig;
    g_activeMitigationController = orig;
    return orig;
}

- (void)setPowerSaveActive:(BOOL)active {
    g_activeMitigationController = self;
    if (insulationCpuMode == 1) { %orig(YES); return; }
    if (insulationCpuMode == 2) { %orig(NO); return; }
    %orig(active);
}

- (void)setCPULevel:(int)level {
    g_activeMitigationController = self;
    if (insulationCpuMode == 1) { %orig(2); return; }
    if (insulationCpuMode == 2) { %orig(0); return; }
    %orig(level);
}

- (void)setCPULowPowerTarget:(int)power {
    g_activeMitigationController = self;
    if (insulationCpuMode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget)); return; }
    %orig(power);
}

- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source {
    g_activeMitigationController = self;
    if (insulationCpuMode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget), source); return; }
    %orig(power, source);
}

- (void)setCPUPowerZoneTarget:(int)power {
    g_activeMitigationController = self;
    if (insulationCpuMode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget)); return; }
    %orig(power);
}

// 顺应系统的自然心跳，同时覆盖数据
- (void)updateCPU {
    g_activeMitigationController = self;
    enforceMitigationState();
    %orig;
}

%end

%ctor {
    NSString *processName = [NSProcessInfo processInfo].processName;
    if (![processName isEqualToString:@"thermalmonitord"]) return;

    %init;
    int token;
    notify_register_dispatch(NOTIFY_CPU_MODE, &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        if (notify_get_state(t, &state) == NOTIFY_STATUS_OK) {
            insulationCpuMode = (NSInteger)state;
            enforceMitigationState();
        }
    });

    uint64_t initialState = 0;
    if (notify_get_state(token, &initialState) == NOTIFY_STATUS_OK) {
        insulationCpuMode = (NSInteger)initialState;
    }

    // 独立定时器，每 1 秒在底层发一次冲击，系统改回多少次我就压回去多少次
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), 1.0 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        enforceMitigationState();
    });
    dispatch_resume(timer);
}

