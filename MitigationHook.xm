
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

// 🟢 严格参考 Insulation 原版逻辑：主动应用并双重写入
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
                [activeMitigationController updateCPU];
            }
            // 双重写入，防止硬件调度器回调覆盖
            if ([activeMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) {
                [activeMitigationController setPowerSaveActive:YES];
            }
            if ([activeMitigationController respondsToSelector:@selector(setCPULevel:)]) {
                [activeMitigationController setCPULevel:2];
            }
        } else if (insulationCpuMode == 2) { // 满血防降频：强制 0
            if ([activeMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) {
                [activeMitigationController setPowerSaveActive:NO];
            }
            if ([activeMitigationController respondsToSelector:@selector(setCPULevel:)]) {
                [activeMitigationController setCPULevel:0];
            }
            if ([activeMitigationController respondsToSelector:@selector(updateCPU)]) {
                [activeMitigationController updateCPU];
            }
        } else if (insulationCpuMode == 0) { // 原生模式：恢复默认
            if ([activeMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) {
                [activeMitigationController setPowerSaveActive:NO];
            }
            if ([activeMitigationController respondsToSelector:@selector(setCPULevel:)]) {
                [activeMitigationController setCPULevel:0];
            }
            if ([activeMitigationController respondsToSelector:@selector(updateCPU)]) {
                [activeMitigationController updateCPU];
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

// 拦截低电量模式开关
- (void)setPowerSaveActive:(BOOL)active {
    activeMitigationController = self;
    if (insulationCpuMode == 1) {
        %orig(YES);
        return;
    } else if (insulationCpuMode == 2) {
        %orig(NO);
        return;
    }
    %orig(active);
}

// 拦截系统降频级别 (低电模式强行压到 2，满血强压到 0)
- (void)setCPULevel:(int)level {
    activeMitigationController = self;
    if (insulationCpuMode == 1) {
        %orig(2);
        return;
    } else if (insulationCpuMode == 2) {
        %orig(0);
        return;
    }
    %orig(level);
}

// 拦截低电功率目标
- (void)setCPULowPowerTarget:(int)power {
    activeMitigationController = self;
    if (insulationCpuMode == 2) {
        %orig(MAX(power, InsulationUnrestrictedPowerTarget));
        return;
    }
    %orig(power);
}

// 拦截温控功率天花板
- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source {
    activeMitigationController = self;
    if (insulationCpuMode == 2) {
        %orig(MAX(power, InsulationUnrestrictedPowerTarget), source);
        return;
    }
    %orig(power, source);
}

// 拦截温度区间功率目标
- (void)setCPUPowerZoneTarget:(int)power {
    activeMitigationController = self;
    if (insulationCpuMode == 2) {
        %orig(MAX(power, InsulationUnrestrictedPowerTarget));
        return;
    }
    %orig(power);
}

%end

%ctor {
    // 严格安全保护：确认类存在，防止非目标系统或进程直接崩溃
    Class cls = objc_getClass("MitigationController");
    if (!cls) {
        return;
    }

    %init;

    // 1. 注册跨进程内核调度频道的监听
    int token;
    notify_register_dispatch(NOTIFY_CPU_MODE, &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        if (notify_get_state(t, &state) == NOTIFY_STATUS_OK) {
            insulationCpuMode = (NSInteger)state;
            applyCurrentMitigationState();
        }
    });

    // 2. 初始化时主动抓取一次状态（应对手机刚开机或进程刚启动的情况）
    uint64_t initialState = 0;
    if (notify_get_state(token, &initialState) == NOTIFY_STATUS_OK) {
        insulationCpuMode = (NSInteger)initialState;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            applyCurrentMitigationState();
        });
    }
}

