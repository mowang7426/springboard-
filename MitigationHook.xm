
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>

#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"

static NSInteger insulationCpuMode = 0;
static const int InsulationUnrestrictedPowerTarget = 65000;
static id g_activeMitigationController = nil;
static id g_commonProduct = nil;

@interface MitigationController : NSObject
- (void)setPowerSaveActive:(BOOL)active;
- (void)setCPULevel:(int)level;
- (void)setCPULowPowerTarget:(int)power;
- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source;
- (void)setCPUPowerZoneTarget:(int)power;
- (void)updateCPU;
@end

@interface CommonProduct : NSObject
- (id)mitigationController;
@end

// 🟢 暴力提取控制器实例
static id getMitigationController() {
    if (g_activeMitigationController) return g_activeMitigationController;
    if (g_commonProduct && [g_commonProduct respondsToSelector:@selector(mitigationController)]) {
        g_activeMitigationController = [g_commonProduct performSelector:@selector(mitigationController)];
        return g_activeMitigationController;
    }
    return nil;
}

// 🟢 安全无延迟下发命令（彻底弃用导致黑洞的 performSelectorOnMainThread）
static void applyCurrentMitigationState(void) {
    id controller = getMitigationController();
    if (!controller) return;

    @try {
        if (insulationCpuMode == 1) { 
            // 模拟低功耗：改为 Level 4 强力压制，效果立竿见影
            if ([controller respondsToSelector:@selector(setPowerSaveActive:)]) [controller setPowerSaveActive:YES];
            if ([controller respondsToSelector:@selector(setCPULevel:)]) [controller setCPULevel:4];
            if ([controller respondsToSelector:@selector(updateCPU)]) [controller updateCPU]; // 直接调用，抛弃黑洞

            // 防御系统回调覆盖，二次双重写入
            if ([controller respondsToSelector:@selector(setPowerSaveActive:)]) [controller setPowerSaveActive:YES];
            if ([controller respondsToSelector:@selector(setCPULevel:)]) [controller setCPULevel:4];
        } else if (insulationCpuMode == 2) { 
            // 满血防降频：强制 0
            if ([controller respondsToSelector:@selector(setPowerSaveActive:)]) [controller setPowerSaveActive:NO];
            if ([controller respondsToSelector:@selector(setCPULevel:)]) [controller setCPULevel:0];
            if ([controller respondsToSelector:@selector(updateCPU)]) [controller updateCPU];
        } else { 
            // 原生模式：恢复默认
            if ([controller respondsToSelector:@selector(setPowerSaveActive:)]) [controller setPowerSaveActive:NO];
            if ([controller respondsToSelector:@selector(updateCPU)]) [controller updateCPU];
        }
    } @catch (NSException *e) {}
}

// 🟢 拦截 CommonProduct 初始化，确保 100% 拿到控制器
%hook CommonProduct
- (instancetype)init {
    id orig = %orig;
    if (orig) {
        g_commonProduct = orig;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            applyCurrentMitigationState();
        });
    }
    return orig;
}
%end

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
    if (insulationCpuMode == 1) { %orig(4); return; } // 强压至 Level 4
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

- (void)updateCPU {
    g_activeMitigationController = self;
    if (insulationCpuMode == 1) {
        [self setPowerSaveActive:YES];
        [self setCPULevel:4];
    } else if (insulationCpuMode == 2) {
        [self setPowerSaveActive:NO];
        [self setCPULevel:0];
    }
    %orig;
}

%end

%ctor {
    // 严格安全保护：只在 thermalmonitord 中运行
    NSString *processName = [NSProcessInfo processInfo].processName;
    if (![processName isEqualToString:@"thermalmonitord"]) return; 

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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            applyCurrentMitigationState();
        });
    }

    // 强力心跳包：每 1.5 秒检查并施加一次降频压制，死死按住 CPU
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), 1.5 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        applyCurrentMitigationState();
    });
    dispatch_resume(timer);
}


