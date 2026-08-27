
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>

#define SBCPU_NOTIFY_MODE "com.yourname.sbcpufloating.cpumode"
#define SBCPU_UNRESTRICTED_POWER_TARGET 65000

static NSInteger gMitigationMode = 0;
static int gNotifyToken = -1;
static id gCommonProduct = nil;
static id gMitigationController = nil;

@interface MitigationController : NSObject
- (void)setPowerSaveActive:(BOOL)active;
- (void)setCPULevel:(int)level;
- (void)updateCPU;
@end

@interface CommonProduct : NSObject
- (id)mitigationController;
@end

// 基础 Hook 工具
static BOOL InstallHook(Class cls, SEL sel, IMP replacement, IMP *originalOut) {
    if (!cls || !sel || !replacement || !originalOut) return NO;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    *originalOut = method_getImplementation(m);
    method_setImplementation(m, replacement);
    return YES;
}

// 1. Hook CommonProduct 拦截 MitigationController 的诞生
static id (*Orig_CommonProduct_init)(id, SEL);
static id Hook_CommonProduct_init(id self, SEL _cmd) {
    id obj = Orig_CommonProduct_init(self, _cmd);
    if (obj) {
        gCommonProduct = obj;
        NSLog(@"[SBCPUMitigation] CommonProduct found");
        if ([obj respondsToSelector:@selector(mitigationController)]) {
            gMitigationController = [obj performSelector:@selector(mitigationController)];
            if (gMitigationController) {
                NSLog(@"[SBCPUMitigation] MitigationController found");
            }
        }
    }
    return obj;
}

// 2. Hook setCPULevel
static void (*Orig_setCPULevel)(id, SEL, int);
static void Hook_setCPULevel(id self, SEL _cmd, int level) {
    gMitigationController = self;
    if (gMitigationMode == 1) {
        NSLog(@"[SBCPUMitigation] setCPULevel %d -> 2", level);
        Orig_setCPULevel(self, _cmd, 2);
        return;
    }
    Orig_setCPULevel(self, _cmd, level);
}

// 3. Hook setPowerSaveActive
static void (*Orig_setPowerSaveActive)(id, SEL, BOOL);
static void Hook_setPowerSaveActive(id self, SEL _cmd, BOOL active) {
    gMitigationController = self;
    if (gMitigationMode == 1) {
        NSLog(@"[SBCPUMitigation] setPowerSaveActive %d -> 1", active);
        Orig_setPowerSaveActive(self, _cmd, YES);
        return;
    }
    Orig_setPowerSaveActive(self, _cmd, active);
}

// 4. Hook setCPULowPowerTarget (Mode 2 用)
static void (*Orig_setCPULowPowerTarget)(id, SEL, int);
static void Hook_setCPULowPowerTarget(id self, SEL _cmd, int power) {
    gMitigationController = self;
    if (gMitigationMode == 2) {
        int newPower = MAX(power, SBCPU_UNRESTRICTED_POWER_TARGET);
        Orig_setCPULowPowerTarget(self, _cmd, newPower);
        return;
    }
    Orig_setCPULowPowerTarget(self, _cmd, power);
}

// 5. Hook setCPUPowerCeiling (Mode 2 用)
static void (*Orig_setCPUPowerCeiling)(id, SEL, int, int);
static void Hook_setCPUPowerCeiling(id self, SEL _cmd, int power, int source) {
    gMitigationController = self;
    if (gMitigationMode == 2) {
        int newPower = MAX(power, SBCPU_UNRESTRICTED_POWER_TARGET);
        Orig_setCPUPowerCeiling(self, _cmd, newPower, source);
        return;
    }
    Orig_setCPUPowerCeiling(self, _cmd, power, source);
}

// 6. Hook setCPUPowerZoneTarget (Mode 2 用)
static void (*Orig_setCPUPowerZoneTarget)(id, SEL, int);
static void Hook_setCPUPowerZoneTarget(id self, SEL _cmd, int power) {
    gMitigationController = self;
    if (gMitigationMode == 2) {
        int newPower = MAX(power, SBCPU_UNRESTRICTED_POWER_TARGET);
        Orig_setCPUPowerZoneTarget(self, _cmd, newPower);
        return;
    }
    Orig_setCPUPowerZoneTarget(self, _cmd, power);
}

// 7. Hook updateCPU
static void (*Orig_updateCPU)(id, SEL);
static void Hook_updateCPU(id self, SEL _cmd) {
    gMitigationController = self;
    if (gMitigationMode == 1) {
        Hook_setPowerSaveActive(self, @selector(setPowerSaveActive:), YES);
        Hook_setCPULevel(self, @selector(setCPULevel:), 2);
    } else if (gMitigationMode == 2) {
        Hook_setPowerSaveActive(self, @selector(setPowerSaveActive:), NO);
    } else if (gMitigationMode == 0) {
        Hook_setPowerSaveActive(self, @selector(setPowerSaveActive:), NO);
    }
    if (Orig_updateCPU) Orig_updateCPU(self, _cmd);
}

// 核心：主动应用降频/防降频策略
static void ApplyMitigationState(void) {
    id controller = gMitigationController;
    
    // 如果还没抓到 Controller，尝试从已有的 CommonProduct 获取
    if (!controller && gCommonProduct && [gCommonProduct respondsToSelector:@selector(mitigationController)]) {
        controller = [gCommonProduct performSelector:@selector(mitigationController)];
        gMitigationController = controller;
    }
    if (!controller) return;

    @try {
        if (gMitigationMode == 1) {
            [controller performSelector:@selector(setPowerSaveActive:) withObject:(id)kCFBooleanTrue];
            void (*setCPULvl)(id, SEL, int) = (void(*)(id, SEL, int))[controller methodForSelector:@selector(setCPULevel:)];
            if (setCPULvl) setCPULvl(controller, @selector(setCPULevel:), 2);
            
            void (*upd)(id, SEL) = (void(*)(id, SEL))[controller methodForSelector:@selector(updateCPU)];
            if (upd) upd(controller, @selector(updateCPU));
        } 
        else if (gMitigationMode == 2) {
            [controller performSelector:@selector(setPowerSaveActive:) withObject:(id)kCFBooleanFalse];
            void (*upd)(id, SEL) = (void(*)(id, SEL))[controller methodForSelector:@selector(updateCPU)];
            if (upd) upd(controller, @selector(updateCPU));
        } 
        else if (gMitigationMode == 0) {
            [controller performSelector:@selector(setPowerSaveActive:) withObject:(id)kCFBooleanFalse];
            void (*upd)(id, SEL) = (void(*)(id, SEL))[controller methodForSelector:@selector(updateCPU)];
            if (upd) upd(controller, @selector(updateCPU));
        }
    } @catch(NSException *e) {
        NSLog(@"[SBCPUMitigation] ApplyMitigationState exception: %@", e);
    }
}

// 构造函数入口
__attribute__((constructor)) static void initSBCPUMitigation() {
    NSLog(@"[SBCPUMitigation] loaded");

    // 1. 设置跨进程通知监听
    notify_register_dispatch(SBCPU_NOTIFY_MODE, &gNotifyToken, dispatch_get_main_queue(), ^(int token) {
        uint64_t state = 0;
        if (notify_get_state(token, &state) == NOTIFY_STATUS_OK) {
            gMitigationMode = (NSInteger)state;
            NSLog(@"[SBCPUMitigation] mode = %ld", (long)gMitigationMode);
            ApplyMitigationState();
        }
    });

    // 2. 初始化时主动抓取一次状态
    uint64_t state = 0;
    if (gNotifyToken >= 0 && notify_get_state(gNotifyToken, &state) == NOTIFY_STATUS_OK) {
        gMitigationMode = (NSInteger)state;
    }

    // 3. 安装 Hook 到 CommonProduct
    Class commonProductCls = objc_getClass("CommonProduct");
    if (commonProductCls) {
        InstallHook(commonProductCls, @selector(init), (IMP)Hook_CommonProduct_init, (IMP *)&Orig_CommonProduct_init);
    }

    // 4. 安装 Hook 到 MitigationController
    Class mitigationCls = objc_getClass("MitigationController");
    if (mitigationCls) {
        InstallHook(mitigationCls, @selector(setPowerSaveActive:), (IMP)Hook_setPowerSaveActive, (IMP *)&Orig_setPowerSaveActive);
        BOOL b2 = InstallHook(mitigationCls, @selector(setCPULevel:), (IMP)Hook_setCPULevel, (IMP *)&Orig_setCPULevel);
        if (b2) NSLog(@"[SBCPUMitigation] setCPULevel hook installed");

        InstallHook(mitigationCls, @selector(setCPULowPowerTarget:), (IMP)Hook_setCPULowPowerTarget, (IMP *)&Orig_setCPULowPowerTarget);
        InstallHook(mitigationCls, @selector(setCPUPowerCeiling:fromDecisionSource:), (IMP)Hook_setCPUPowerCeiling, (IMP *)&Orig_setCPUPowerCeiling);
        InstallHook(mitigationCls, @selector(setCPUPowerZoneTarget:), (IMP)Hook_setCPUPowerZoneTarget, (IMP *)&Orig_setCPUPowerZoneTarget);
        InstallHook(mitigationCls, @selector(updateCPU), (IMP)Hook_updateCPU, (IMP *)&Orig_updateCPU);
    }

    // 5. 定时检查并二次应用状态 (防备被覆盖)
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), 1.5 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        ApplyMitigationState();
    });
    dispatch_resume(timer);
}
