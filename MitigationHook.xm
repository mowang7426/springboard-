
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>

#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"

static NSInteger insulationCpuMode = 0;
static const int InsulationUnrestrictedPowerTarget = 65000;
static __weak id activeMitigationController = nil;

@interface MitigationController : NSObject
- (void)setPowerSaveActive:(BOOL)active;
- (void)setCPULevel:(int)level;
- (void)setCPULowPowerTarget:(int)power;
- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source;
- (void)setCPUPowerZoneTarget:(int)power;
- (void)updateCPU;
@end

// 🟢 安全应用状态（必须确保在安全线程调用，防止守护进程崩溃）
static void applyCurrentMitigationState(void) {
    if (!activeMitigationController) return;
    @try {
        if (insulationCpuMode == 1) { // 模拟低功耗：锁 CPU Level 2
            if ([activeMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) {
                [activeMitigationController setPowerSaveActive:YES];
            }
            if ([activeMitigationController respondsToSelector:@selector(setCPULevel:)]) {
                [activeMitigationController setCPULevel:2];
            }
            if ([activeMitigationController respondsToSelector:@selector(updateCPU)]) {
                [activeMitigationController performSelectorOnMainThread:@selector(updateCPU) withObject:nil waitUntilDone:NO];
            }
        } else if (insulationCpuMode == 2) { // 满血防降频：强制 0
            if ([activeMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) {
                [activeMitigationController setPowerSaveActive:NO];
            }
            if ([activeMitigationController respondsToSelector:@selector(setCPULevel:)]) {
                [activeMitigationController setCPULevel:0];
            }
            if ([activeMitigationController respondsToSelector:@selector(updateCPU)]) {
                [activeMitigationController performSelectorOnMainThread:@selector(updateCPU) withObject:nil waitUntilDone:NO];
            }
        } else if (insulationCpuMode == 0) { // 原生模式：恢复默认
            if ([activeMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) {
                [activeMitigationController setPowerSaveActive:NO];
            }
            if ([activeMitigationController respondsToSelector:@selector(setCPULevel:)]) {
                [activeMitigationController setCPULevel:0];
            }
            if ([activeMitigationController respondsToSelector:@selector(updateCPU)]) {
                [activeMitigationController performSelectorOnMainThread:@selector(updateCPU) withObject:nil waitUntilDone:NO];
            }
        }
    } @catch (NSException *e) {}
}

%hook MitigationController

- (instancetype)init {
    id orig = %orig;
    activeMitigationController = orig;
    return orig;
}

- (void)setPowerSaveActive:(BOOL)active {
    activeMitigationController = self;
    if (insulationCpuMode == 1) { %orig(YES); return; }
    if (insulationCpuMode == 2) { %orig(NO); return; }
    %orig(active);
}

- (void)setCPULevel:(int)level {
    activeMitigationController = self;
    if (insulationCpuMode == 1) { %orig(2); return; }
    if (insulationCpuMode == 2) { %orig(0); return; }
    %orig(level);
}

- (void)setCPULowPowerTarget:(int)power {
    activeMitigationController = self;
    if (insulationCpuMode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget)); return; }
    %orig(power);
}

- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source {
    activeMitigationController = self;
    if (insulationCpuMode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget), source); return; }
    %orig(power, source);
}

- (void)setCPUPowerZoneTarget:(int)power {
    activeMitigationController = self;
    if (insulationCpuMode == 2) { %orig(MAX(power, InsulationUnrestrictedPowerTarget)); return; }
    %orig(power);
}
%end

%ctor {
    Class cls = objc_getClass("MitigationController");
    if (!cls) return;

    %init;
    int token;
    notify_register_dispatch(NOTIFY_CPU_MODE, &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        if (notify_get_state(t, &state) == NOTIFY_STATUS_OK) {
            insulationCpuMode = (NSInteger)state;
            applyCurrentMitigationState();
        }
    });

    uint64_t initialState = 0;
    if (notify_get_state(token, &initialState) == NOTIFY_STATUS_OK) {
        insulationCpuMode = (NSInteger)initialState;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            applyCurrentMitigationState();
        });
    }
}

