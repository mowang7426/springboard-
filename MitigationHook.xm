
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>

#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"

static NSInteger insulationCpuMode = 0;
static const int InsulationUnrestrictedPowerTarget = 65000;

@interface MitigationController : NSObject
- (void)setPowerSaveActive:(BOOL)active;
- (void)setCPULevel:(int)level;
- (void)setCPULowPowerTarget:(int)power;
- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source;
- (void)setCPUPowerZoneTarget:(int)power;
- (void)updateCPU;
@end

%hook MitigationController

- (void)setPowerSaveActive:(BOOL)active {
    if (insulationCpuMode == 1) { %orig(YES); return; }
    if (insulationCpuMode == 2) { %orig(NO); return; }
    %orig(active);
}

// ⚠️ 严禁使用 Level 4，必须使用苹果底层认可的 Level 2 才能持久锁住
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

// 顺应系统的自然心跳，在系统每次准备刷新硬件前，强行覆盖其内部数据
- (void)updateCPU {
    if (insulationCpuMode == 1) {
        [self setPowerSaveActive:YES];
        [self setCPULevel:2];
    } else if (insulationCpuMode == 2) {
        [self setPowerSaveActive:NO];
        [self setCPULevel:0];
    }
    %orig;
}

%end

%ctor {
    // 严格安全保护：确保仅在 thermalmonitord 守护进程内生效
    NSString *processName = [NSProcessInfo processInfo].processName;
    if (![processName isEqualToString:@"thermalmonitord"]) return;

    %init;

    // 监听来自桌面的模式切换指令
    int token;
    notify_register_dispatch(NOTIFY_CPU_MODE, &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        if (notify_get_state(t, &state) == NOTIFY_STATUS_OK) {
            insulationCpuMode = (NSInteger)state;
            // 收到指令后不做任何危险的立即刷新操作，
            // 而是等待系统自身下一次（1秒内）触发 updateCPU 时自然接管，彻底解决掉线问题。
        }
    });

    uint64_t initialState = 0;
    if (notify_get_state(token, &initialState) == NOTIFY_STATUS_OK) {
        insulationCpuMode = (NSInteger)initialState;
    }
}
