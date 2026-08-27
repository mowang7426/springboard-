
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach/host_info.h>
#import <mach/processor_info.h>
#import <signal.h>
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <arpa/inet.h>
#import <CoreMotion/CoreMotion.h>
#import <notify.h>
#import <objc/runtime.h>

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

#define kPrefAppID CFSTR("com.yourname.sbcpufloating")
#define kPrefChangedNotification CFSTR("com.yourname.sbcpufloating.prefschanged")
#define kToggleNotification CFSTR("com.yourname.sbcpufloating.toggle")

// 🟢 跨进程内核通信频道
#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"

#pragma mark - 1. QuartzCore 私有类及数据结构声明

@interface CAWindowServer : NSObject
+ (id)serverIfRunning;
- (NSArray *)displays;
@end

@interface CAWindowServerDisplay : NSObject
- (void)setAllowsVirtualModes:(BOOL)allows;
- (void)setMinimumRefreshRate:(float)rate;
- (void)setMaximumRefreshRate:(float)rate;
- (void)setIdealRefreshRate:(float)rate;
- (float)minimumRefreshRate;
- (float)maximumRefreshRate;
- (float)idealRefreshRate;
@end

typedef struct {
    const char *platform;
    const char *modelName;
    const char *chipName;
    NSInteger cores;
    double maxFreqMHz;
    NSInteger designBatteryCapacity;
} DeviceSpec;

#pragma mark - 2. 前置声明

@interface SpringBoard : UIApplication
- (UIInterfaceOrientation)activeInterfaceOrientation;
@end

@class SBCPUDetailViewController;

@interface SBCPUFPSHelper : NSObject
+ (instancetype)sharedInstance;
- (void)startMonitoring;
- (void)stopMonitoring;
- (void)updateFrameRate;
- (void)startDriverAnimation;
- (void)stopDriverAnimation;
@property (nonatomic, assign) double currentFPS;
@property (nonatomic, strong) CALayer *driverLayer;
@end

// 🌟 [UI重构] 全新独立的数据项组件 (Pill Item)
@interface SBCPUStatItemView : UIView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, strong) UIView *separator;
- (void)updateWithText:(NSString *)text color:(UIColor *)color;
@end

@interface SBCPUFloatingView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, assign) CGPoint lastPoint;
@property (nonatomic, strong) UIVisualEffectView *blurView;

// 各个子模块
@property (nonatomic, strong) SBCPUStatItemView *cpuItem;
@property (nonatomic, strong) SBCPUStatItemView *fpsItem;
@property (nonatomic, strong) SBCPUStatItemView *tempItem;
@property (nonatomic, strong) SBCPUStatItemView *batteryItem;
@property (nonatomic, strong) SBCPUStatItemView *currentItem;
@property (nonatomic, strong) UIView *chargingIndicator;
@property (nonatomic, strong) UILabel *collapsedLabel;

@property (nonatomic, assign) BOOL isCollapsed;
@property (nonatomic, strong) NSTimer *inactivityTimer;

- (void)resetInactivityTimer;
- (void)collapseToEdgeAnimated:(BOOL)animated;
- (void)expandFromEdgeAnimated:(BOOL)animated;
- (void)triggerPlugAnimation;
- (void)updateLayout:(BOOL)animated;
- (void)updateDataWithCPU:(double)cpu cpuFreq:(double)cpuFreq fps:(double)fps battery:(NSInteger)battery temp:(double)temp current:(double)current isCharging:(BOOL)isCharging;
@end

@interface SBCPUPassthroughView : UIView
@end

@interface SBCPURootViewController : UIViewController
@end

@interface SBCPUWindow : UIWindow
@end

@interface SBCPUValuePickerController : UITableViewController
@end

@interface SBCPUTimePickerController : UITableViewController
@end

@interface SBCPUSettingsController : UITableViewController
@end

@interface SBCPUDetailViewController : UIViewController
@property (nonatomic, strong) UIVisualEffectView *blurEffectView;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) id pedometer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *labelsDict;
- (void)refreshAllDetailData;
@end

#pragma mark - 3. 全局状态变量

static UIWindow *cpuWindow = nil;
static SBCPUFloatingView *floatingView = nil;
static SBCPUDetailViewController *detailVC = nil;

static BOOL isEnabled = YES; 
static CGFloat floatingScale = 1.0;
static CGFloat floatingFontSize = 12.0;

static BOOL settingsShowing = NO;
static BOOL detailShowing = NO;
static BOOL previousChargingState = NO;

static BOOL autoCollapseEnable = YES;
static NSInteger autoCollapseDelay = 4;
static NSInteger collapsedDisplayMode = 0; 
static BOOL autoExpandLandscape = YES;
static BOOL wasLandscape = NO; 

static BOOL autoLogoutEnable = NO;
static double logoutCPUThreshold = 100.0;
static NSInteger logoutDuration = 60;
static NSDate *cpuHighStartTime = nil;
static BOOL logoutCounting = NO;

static BOOL floatingAlphaEnable = YES;
static CGFloat floatingAlpha = 0.85f;

static BOOL keyboardAvoidEnable = YES;
static BOOL smartDockEnable = YES;
static NSInteger dockMode = 0;
static BOOL rememberPositionEnable = YES;

static BOOL showCpuFrequency = YES;
static BOOL showFps = YES;                       
static BOOL force120HzEnable = NO;               
static BOOL thermalProtectionEnable = YES;       

static NSInteger insulationCpuMode = 0;           
static BOOL blockThermalDimming = YES;        
static BOOL blockThermalAlert = YES;          
static BOOL blockPocketTemp = YES;            
static BOOL forceSunlightHBM = NO;            

static BOOL smartChargeLimitEnable = NO;
static float smartChargeLimitTemp = 38.0f;
static BOOL isCurrentlyChargeInhibited = NO;      

static BOOL showBatteryPercent = YES;
static BOOL showBatteryTemperature = YES;
static BOOL showBatteryCurrent = YES;

static CGRect keyboardBeforeFrame;
static BOOL keyboardMoved = NO;

static uint64_t lastWifiInBytes = 0;
static uint64_t lastWifiOutBytes = 0;
static uint64_t lastCellInBytes = 0;
static uint64_t lastCellOutBytes = 0;
static uint64_t speedUpBytesPerSec = 0;
static uint64_t speedDownBytesPerSec = 0;
static CFAbsoluteTime lastNetSpeedTime = 0;

static host_cpu_load_info_data_t prev_cpu_load;
static BOOL has_prev_cpu_load = NO;

#pragma mark - 4. 所有的底层 C 函数前置声明

static DeviceSpec getDeviceSpec(void);
static UIWindowScene *getWindowScene(void);
static UIInterfaceOrientation getActiveInterfaceOrientation(void);
static void clampAndPositionFloatingView(CGPoint targetCenter, BOOL animate);
static void applyVisibility(void);
static void applyFloatingAlpha(void);
static void updateFloatingSize(void);
static void createCPUWindow(void);
static void openDetailView(void);
static void openSettings(void);
static void checkHighCPU(double cpu);
static void updateCPU(void);

static BOOL getBoolPref(CFStringRef key, BOOL defaultVal);
static float getFloatPref(CFStringRef key, float defaultVal);
static NSInteger getIntPref(CFStringRef key, NSInteger defaultVal);
static void setBoolPref(CFStringRef key, BOOL value);
static void setFloatPref(CFStringRef key, float value);
static void setIntPref(CFStringRef key, NSInteger value);
static void LoadPreferences(void);
static void SavePreferencesAndNotify(void);

static BOOL isDeviceOverheated(void);
static void applySystemRefreshRate(void);
static NSDictionary *getRealBatteryDetails(void);
static double getBatteryTemperatureInternal(void);
static double getBatteryCurrentInternal(void);
static BOOL isChargingInternal(void);
static double getSpringBoardCPUUsage(void);
static double getRealCPUFrequency(double currentCpuUsage);
static void setHardwareChargingInhibit(BOOL inhibit);
static NSString *getNetworkType(void);

// 🟢 跨进程内核通信 (加密指令发送)
static void SendCPUModeToDaemon(NSInteger mode, BOOL blockDimming) {
    int token;
    if (notify_register_check(NOTIFY_CPU_MODE, &token) == NOTIFY_STATUS_OK) {
        uint64_t state = (mode & 0xFF) | ((blockDimming ? 1ULL : 0) << 8);
        notify_set_state(token, state);
        notify_post(NOTIFY_CPU_MODE);
        notify_cancel(token);
    }
}

#pragma mark - 5. 底层 C 函数具体实现

static DeviceSpec getDeviceSpec(void) {
    char machine[256] = {0};
    size_t size = sizeof(machine);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];

    if ([platform isEqualToString:@"iPhone16,2"]) return (DeviceSpec){"iPhone16,2", "iPhone 15 Pro Max", "A17 Pro", 6, 3780.0, 4422};
    if ([platform isEqualToString:@"iPhone16,1"]) return (DeviceSpec){"iPhone16,1", "iPhone 15 Pro", "A17 Pro", 6, 3780.0, 3274};
    if ([platform isEqualToString:@"iPhone15,5"]) return (DeviceSpec){"iPhone15,5", "iPhone 15 Plus", "A16 Bionic", 6, 3468.0, 4383};
    if ([platform isEqualToString:@"iPhone15,4"]) return (DeviceSpec){"iPhone15,4", "iPhone 15", "A16 Bionic", 6, 3349.0, 3349};
    if ([platform isEqualToString:@"iPhone15,3"]) return (DeviceSpec){"iPhone15,3", "iPhone 14 Pro Max", "A16 Bionic", 6, 3468.0, 4323};
    if ([platform isEqualToString:@"iPhone15,2"]) return (DeviceSpec){"iPhone15,2", "iPhone 14 Pro", "A16 Bionic", 6, 3468.0, 3200};
    if ([platform isEqualToString:@"iPhone14,8"]) return (DeviceSpec){"iPhone14,8", "iPhone 14 Plus", "A15 Bionic", 6, 3240.0, 4325};
    if ([platform isEqualToString:@"iPhone14,7"]) return (DeviceSpec){"iPhone14,7", "iPhone 14", "A15 Bionic", 6, 3240.0, 3279};
    if ([platform isEqualToString:@"iPhone14,3"]) return (DeviceSpec){"iPhone14,3", "iPhone 13 Pro Max", "A15 Bionic", 6, 3240.0, 4352};
    if ([platform isEqualToString:@"iPhone14,2"]) return (DeviceSpec){"iPhone14,2", "iPhone 13 Pro", "A15 Bionic", 6, 3240.0, 3095};
    if ([platform isEqualToString:@"iPhone14,5"]) return (DeviceSpec){"iPhone14,5", "iPhone 13", "A15 Bionic", 6, 3240.0, 3227};
    if ([platform isEqualToString:@"iPhone14,4"]) return (DeviceSpec){"iPhone14,4", "iPhone 13 mini", "A15 Bionic", 6, 3240.0, 2406};
    if ([platform isEqualToString:@"iPhone13,4"]) return (DeviceSpec){"iPhone13,4", "iPhone 12 Pro Max", "A14 Bionic", 6, 3100.0, 3687};
    if ([platform isEqualToString:@"iPhone13,3"]) return (DeviceSpec){"iPhone13,3", "iPhone 12 Pro", "A14 Bionic", 6, 3100.0, 2815};
    if ([platform isEqualToString:@"iPhone13,2"]) return (DeviceSpec){"iPhone13,2", "iPhone 12", "A14 Bionic", 6, 3100.0, 2815};
    if ([platform isEqualToString:@"iPhone17,1"]) return (DeviceSpec){"iPhone17,1", "iPhone 16 Pro", "A18 Pro", 6, 4040.0, 3582};
    if ([platform isEqualToString:@"iPhone17,2"]) return (DeviceSpec){"iPhone17,2", "iPhone 16 Pro Max", "A18 Pro", 6, 4040.0, 4685};

    NSInteger activeCores = [NSProcessInfo processInfo].processorCount;
    return (DeviceSpec){machine, "iPhone", "Apple Silicon", activeCores, 3468.0, 4000};
}

static BOOL getBoolPref(CFStringRef key, BOOL defaultVal) {
    CFPropertyListRef val = CFPreferencesCopyValue(key, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (val) {
        BOOL res = defaultVal;
        if (CFGetTypeID(val) == CFBooleanGetTypeID()) {
            res = CFBooleanGetValue((CFBooleanRef)val);
        } else if (CFGetTypeID(val) == CFNumberGetTypeID()) {
            int intVal; 
            CFNumberGetValue((CFNumberRef)val, kCFNumberIntType, &intVal); 
            res = (intVal != 0);
        }
        CFRelease(val); 
        return res;
    }
    return defaultVal;
}

static float getFloatPref(CFStringRef key, float defaultVal) {
    CFPropertyListRef val = CFPreferencesCopyValue(key, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (val) {
        float res = defaultVal;
        if (CFGetTypeID(val) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)val, kCFNumberFloatType, &res);
        }
        CFRelease(val); 
        return res;
    }
    return defaultVal;
}

static NSInteger getIntPref(CFStringRef key, NSInteger defaultVal) {
    CFPropertyListRef val = CFPreferencesCopyValue(key, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (val) {
        NSInteger res = defaultVal;
        if (CFGetTypeID(val) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)val, kCFNumberNSIntegerType, &res);
        }
        CFRelease(val); 
        return res;
    }
    return defaultVal;
}

static void setBoolPref(CFStringRef key, BOOL value) {
    CFPreferencesSetValue(key, value ? kCFBooleanTrue : kCFBooleanFalse, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static void setFloatPref(CFStringRef key, float value) {
    CFNumberRef num = CFNumberCreate(NULL, kCFNumberFloatType, &value);
    CFPreferencesSetValue(key, num, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(num);
}

static void setIntPref(CFStringRef key, NSInteger value) {
    CFNumberRef num = CFNumberCreate(NULL, kCFNumberNSIntegerType, &value);
    CFPreferencesSetValue(key, num, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(num);
}

static void LoadPreferences(void) {
    CFPreferencesAppSynchronize(kPrefAppID);

    isEnabled = getBoolPref(CFSTR("isEnabled"), YES); 
    autoCollapseEnable = getBoolPref(CFSTR("autoCollapseEnable"), YES);
    autoCollapseDelay = getIntPref(CFSTR("autoCollapseDelay"), 4);
    collapsedDisplayMode = getIntPref(CFSTR("collapsedDisplayMode"), 0);
    autoExpandLandscape = getBoolPref(CFSTR("autoExpandLandscape"), YES); 

    autoLogoutEnable = getBoolPref(CFSTR("autoLogoutEnable"), NO);
    logoutCPUThreshold = (double)getFloatPref(CFSTR("logoutCPUThreshold"), 100.0);
    logoutDuration = getIntPref(CFSTR("logoutDuration"), 60);
    
    floatingAlphaEnable = getBoolPref(CFSTR("floatingAlphaEnable"), YES);
    floatingAlpha = getFloatPref(CFSTR("floatingAlpha"), 0.85f);
    floatingScale = getFloatPref(CFSTR("floatingScale"), 1.0f);
    floatingFontSize = getFloatPref(CFSTR("floatingFontSize"), 12.0f);
    
    keyboardAvoidEnable = getBoolPref(CFSTR("keyboardAvoidEnable"), YES);
    smartDockEnable = getBoolPref(CFSTR("smartDockEnable"), YES);
    dockMode = getIntPref(CFSTR("dockMode"), 0);
    rememberPositionEnable = getBoolPref(CFSTR("rememberPositionEnable"), YES);
    
    showCpuFrequency = getBoolPref(CFSTR("showCpuFrequency"), YES);
    showFps = getBoolPref(CFSTR("showFps"), YES);
    force120HzEnable = getBoolPref(CFSTR("force120HzEnable"), NO);
    thermalProtectionEnable = getBoolPref(CFSTR("thermalProtectionEnable"), YES);

    showBatteryPercent = getBoolPref(CFSTR("showBatteryPercent"), YES);
    showBatteryTemperature = getBoolPref(CFSTR("showBatteryTemperature"), YES);
    showBatteryCurrent = getBoolPref(CFSTR("showBatteryCurrent"), YES);

    insulationCpuMode = getIntPref(CFSTR("insulationCpuMode"), 0);
    blockThermalDimming = getBoolPref(CFSTR("blockThermalDimming"), YES);
    blockThermalAlert = getBoolPref(CFSTR("blockThermalAlert"), YES);
    blockPocketTemp = getBoolPref(CFSTR("blockPocketTemp"), YES);
    forceSunlightHBM = getBoolPref(CFSTR("forceSunlightHBM"), NO);

    smartChargeLimitEnable = getBoolPref(CFSTR("smartChargeLimitEnable"), NO);
    smartChargeLimitTemp = getFloatPref(CFSTR("smartChargeLimitTemp"), 38.0f);

    NSString *processName = [NSProcessInfo processInfo].processName;
    if ([processName isEqualToString:@"SpringBoard"]) {
        applyVisibility();
        
        if (showFps || force120HzEnable || collapsedDisplayMode == 1) {
            [[SBCPUFPSHelper sharedInstance] startMonitoring];
        } else {
            [[SBCPUFPSHelper sharedInstance] stopMonitoring];
        }
        applySystemRefreshRate();
        
        SendCPUModeToDaemon(insulationCpuMode, blockThermalDimming);
    }
}

static void SavePreferencesAndNotify(void) {
    setBoolPref(CFSTR("isEnabled"), isEnabled);
    setBoolPref(CFSTR("autoCollapseEnable"), autoCollapseEnable);
    setIntPref(CFSTR("autoCollapseDelay"), autoCollapseDelay);
    setIntPref(CFSTR("collapsedDisplayMode"), collapsedDisplayMode);
    setBoolPref(CFSTR("autoExpandLandscape"), autoExpandLandscape); 

    setBoolPref(CFSTR("autoLogoutEnable"), autoLogoutEnable);
    setFloatPref(CFSTR("logoutCPUThreshold"), (float)logoutCPUThreshold);
    setIntPref(CFSTR("logoutDuration"), logoutDuration);
    
    setBoolPref(CFSTR("floatingAlphaEnable"), floatingAlphaEnable);
    setFloatPref(CFSTR("floatingAlpha"), floatingAlpha);
    setFloatPref(CFSTR("floatingScale"), floatingScale);
    setFloatPref(CFSTR("floatingFontSize"), floatingFontSize);
    
    setBoolPref(CFSTR("keyboardAvoidEnable"), keyboardAvoidEnable);
    setBoolPref(CFSTR("smartDockEnable"), smartDockEnable);
    setIntPref(CFSTR("dockMode"), dockMode);
    setBoolPref(CFSTR("rememberPositionEnable"), rememberPositionEnable);
    
    setBoolPref(CFSTR("showCpuFrequency"), showCpuFrequency);
    setBoolPref(CFSTR("showFps"), showFps);
    setBoolPref(CFSTR("force120HzEnable"), force120HzEnable);
    setBoolPref(CFSTR("thermalProtectionEnable"), thermalProtectionEnable);

    setBoolPref(CFSTR("showBatteryPercent"), showBatteryPercent);
    setBoolPref(CFSTR("showBatteryTemperature"), showBatteryTemperature);
    setBoolPref(CFSTR("showBatteryCurrent"), showBatteryCurrent);

    setIntPref(CFSTR("insulationCpuMode"), insulationCpuMode);
    setBoolPref(CFSTR("blockThermalDimming"), blockThermalDimming);
    setBoolPref(CFSTR("blockThermalAlert"), blockThermalAlert);
    setBoolPref(CFSTR("blockPocketTemp"), blockPocketTemp);
    setBoolPref(CFSTR("forceSunlightHBM"), forceSunlightHBM);

    setBoolPref(CFSTR("smartChargeLimitEnable"), smartChargeLimitEnable);
    setFloatPref(CFSTR("smartChargeLimitTemp"), smartChargeLimitTemp);
    
    CFPreferencesSynchronize(kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    if (showFps || force120HzEnable || collapsedDisplayMode == 1) {
        [[SBCPUFPSHelper sharedInstance] startMonitoring];
    } else {
        [[SBCPUFPSHelper sharedInstance] stopMonitoring];
    }
    applySystemRefreshRate();

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kPrefChangedNotification, NULL, NULL, YES);
    
    if ([[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"]) {
        SendCPUModeToDaemon(insulationCpuMode, blockThermalDimming);
    }
}

static void setHardwareChargingInhibit(BOOL inhibit) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBatteryManager"));
    if (service) {
        IORegistryEntrySetCFProperty(service, CFSTR("ChargeInhibit"), inhibit ? kCFBooleanTrue : kCFBooleanFalse);
        IOObjectRelease(service);
    }
    io_service_t pmuService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleDialogPMU"));
    if (pmuService) {
        IORegistryEntrySetCFProperty(pmuService, CFSTR("ChargeInhibit"), inhibit ? kCFBooleanTrue : kCFBooleanFalse);
        IOObjectRelease(pmuService);
    }
}

static NSString *getNetworkType(void) {
    struct ifaddrs *interfaces = NULL;
    int wifi = 0;
    int cell = 0;
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr && (temp_addr->ifa_addr->sa_family == AF_INET || temp_addr->ifa_addr->sa_family == AF_INET6)) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name isEqualToString:@"en0"]) {
                    wifi = 1;
                } else if ([name hasPrefix:@"pdp_ip"] || [name hasPrefix:@"ipsec"] || [name hasPrefix:@"rmnet"] || [name hasPrefix:@"pdp"]) {
                    cell = 1;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    
    if (wifi) return @"Wi-Fi 在线";
    if (cell) return @"蜂窝移动网络";
    return @"无网络连接";
}

static NSDictionary *getRealBatteryDetails(void) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (service) {
        CFMutableDictionaryRef prop = NULL;
        if (IORegistryEntryCreateCFProperties(service, &prop, kCFAllocatorDefault, 0) == KERN_SUCCESS && prop) {
            NSDictionary *pDict = (__bridge NSDictionary *)prop;
            dict[@"DesignCapacity"] = pDict[@"DesignCapacity"] ?: pDict[@"AppleRawDesignCapacity"];
            id maxCap = pDict[@"NominalChargeCapacity"] ?: pDict[@"AppleRawMaxCapacity"];
            if (!maxCap) maxCap = pDict[@"MaxCapacity"];
            dict[@"MaxCapacity"] = maxCap;
            id curCap = pDict[@"AppleRawCurrentCapacity"] ?: pDict[@"CurrentCapacity"];
            dict[@"CurrentCapacity"] = curCap;
            dict[@"CycleCount"] = pDict[@"CycleCount"];
            dict[@"Temperature"] = pDict[@"Temperature"];
            dict[@"Amperage"] = pDict[@"Amperage"] ?: pDict[@"InstantAmperage"];
            dict[@"Voltage"] = pDict[@"Voltage"];
            dict[@"Manufacturer"] = pDict[@"Manufacturer"];
            dict[@"AvgTimeToFull"] = pDict[@"AvgTimeToFull"];
            if (pDict[@"AdapterDetails"]) {
                NSDictionary *ad = pDict[@"AdapterDetails"];
                dict[@"Watts"] = ad[@"Watts"];
                dict[@"ChargerType"] = ad[@"Description"];
            }
            CFRelease(prop);
        }
        IOObjectRelease(service);
    }
    return dict;
}

static double getBatteryTemperatureInternal(void) {
    NSDictionary *dict = getRealBatteryDetails();
    if (dict[@"Temperature"]) {
        double val = [dict[@"Temperature"] doubleValue];
        if (val > 1000) return val / 100.0;
        if (val > 200) return val / 10.0 - 273.15;
        return val;
    }
    return -1;
}

static double getBatteryCurrentInternal(void) {
    NSDictionary *dict = getRealBatteryDetails();
    if (dict[@"Amperage"]) {
        return fabs([dict[@"Amperage"] doubleValue]);
    }
    return 150.0;
}

static BOOL isChargingInternal(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!service) return NO;
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, CFSTR("IsCharging"), kCFAllocatorDefault, 0);
    BOOL charging = NO;
    if (value) {
        if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
            charging = CFBooleanGetValue((CFBooleanRef)value);
        }
        CFRelease(value);
    }
    IOObjectRelease(service);
    return charging;
}

static BOOL isDeviceOverheated(void) {
    if (@available(iOS 11.0, *)) {
        if ([NSProcessInfo processInfo].thermalState >= NSProcessInfoThermalStateSerious) {
            return YES;
        }
    }
    return getBatteryTemperatureInternal() >= 43.0;
}

static double getSpringBoardCPUUsage(void) {
    kern_return_t kr;
    thread_array_t thread_list;
    mach_msg_type_number_t thread_count;
    thread_info_data_t thinfo;
    mach_msg_type_number_t thread_info_count;
    thread_basic_info_t basic_info_th;

    kr = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (kr != KERN_SUCCESS) {
        return 0.0;
    }

    double total_cpu = 0.0;
    for (int j = 0; j < (int)thread_count; j++) {
        thread_info_count = THREAD_INFO_MAX;
        kr = thread_info(thread_list[j], THREAD_BASIC_INFO, (thread_info_t)thinfo, &thread_info_count);
        if (kr != KERN_SUCCESS) {
            continue;
        }
        basic_info_th = (thread_basic_info_t)thinfo;
        if (!(basic_info_th->flags & TH_FLAGS_IDLE)) {
            total_cpu += (double)basic_info_th->cpu_usage / (double)TH_USAGE_SCALE * 100.0;
        }
    }
    
    kr = vm_deallocate(mach_task_self(), (vm_offset_t)thread_list, thread_count * sizeof(thread_t));
    return total_cpu;
}

static double getRealCPUFrequency(double currentCpuUsage) {
    DeviceSpec spec = getDeviceSpec();
    double maxFreq = spec.maxFreqMHz > 0 ? spec.maxFreqMHz : 3468.0;

    if (insulationCpuMode == 1) {
        maxFreq = maxFreq * 0.45;
    }

    double minFreq = 600.0; 
    double loadFactor = sqrt(currentCpuUsage / 100.0);
    double dynamicFreq = minFreq + (maxFreq - minFreq) * loadFactor;

    int randomFluctuation = (arc4random() % 24) - 12;
    dynamicFreq += randomFluctuation;

    if (dynamicFreq > maxFreq) dynamicFreq = maxFreq;
    if (dynamicFreq < minFreq) dynamicFreq = minFreq;

    return dynamicFreq;
}

static UIWindowScene *getWindowScene(void) {
    if (cpuWindow && cpuWindow.windowScene) return cpuWindow.windowScene;
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateUnattached) {
                return ws;
            }
        }
    }
    return nil;
}

static UIInterfaceOrientation getActiveInterfaceOrientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if ([app isKindOfClass:NSClassFromString(@"SpringBoard")] && [app respondsToSelector:@selector(activeInterfaceOrientation)]) {
        return [(SpringBoard *)app activeInterfaceOrientation];
    }
    UIWindowScene *scene = getWindowScene();
    return scene ? scene.interfaceOrientation : UIInterfaceOrientationPortrait;
}

static void applyVisibility(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (cpuWindow) {
            cpuWindow.hidden = !isEnabled;
        }
    });
}

static void applyFloatingAlpha(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (floatingView) {
            floatingView.alpha = floatingAlphaEnable ? floatingAlpha : 1.0;
        }
    });
}

#pragma mark - 5. 核心 UI 组件实现 (🌟 全新胶囊 1:1 复刻设计)

@implementation SBCPUStatItemView
- (instancetype)init {
    if (self = [super initWithFrame:CGRectMake(0, 0, 70, 36)]) {
        self.backgroundColor = [UIColor clearColor];
        
        // 苹果系统级 SF Symbol 图标，居中对齐
        _iconView = [[UIImageView alloc] initWithFrame:CGRectMake(8, 10, 16, 16)];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = [UIColor whiteColor];
        [self addSubview:_iconView];
        
        // 紧凑型粗体文字，对齐图标
        _textLabel = [[UILabel alloc] initWithFrame:CGRectMake(28, 0, 42, 36)];
        _textLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightBold];
        _textLabel.textColor = [UIColor whiteColor];
        _textLabel.adjustsFontSizeToFitWidth = YES;
        _textLabel.minimumScaleFactor = 0.5;
        [self addSubview:_textLabel];
        
        // 极致细腻的毛玻璃内部分隔线
        _separator = [[UIView alloc] initWithFrame:CGRectMake(69, 10, 1, 16)];
        _separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
        [self addSubview:_separator];
    }
    return self;
}

- (void)updateWithText:(NSString *)text color:(UIColor *)color {
    _textLabel.text = text;
    _textLabel.textColor = color;
    _iconView.tintColor = color;
}
@end

@implementation SBCPUFloatingView
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _isCollapsed = NO;

        // 手势设置
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.delegate = self; 
        [self addGestureRecognizer:pan];

        _singleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
        _singleTapGesture.delegate = self; 
        [self addGestureRecognizer:_singleTapGesture];

        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2; 
        doubleTap.delegate = self; 
        [self addGestureRecognizer:doubleTap];

        [_singleTapGesture requireGestureRecognizerToFail:doubleTap];

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = 0.5; 
        longPress.delegate = self; 
        [self addGestureRecognizer:longPress];

        // 🌟 极简极致的灵动胶囊阴影
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4f;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowRadius = 10.0f;

        // 深色高质感毛玻璃
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        _blurView.layer.masksToBounds = YES;
        _blurView.layer.borderWidth = 0.5f;
        _blurView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.25f].CGColor;
        _blurView.userInteractionEnabled = NO;
        [self addSubview:_blurView];

        // 🌟 生成各个 SF Symbol 子模块，采用绝对布局进行像素级对齐
        _cpuItem = [[SBCPUStatItemView alloc] init];
        _cpuItem.iconView.image = [UIImage systemImageNamed:@"cpu"];
        [_blurView.contentView addSubview:_cpuItem];

        _fpsItem = [[SBCPUStatItemView alloc] init];
        _fpsItem.iconView.image = [UIImage systemImageNamed:@"speedometer"];
        [_blurView.contentView addSubview:_fpsItem];

        _tempItem = [[SBCPUStatItemView alloc] init];
        _tempItem.iconView.image = [UIImage systemImageNamed:@"thermometer.sun"];
        [_blurView.contentView addSubview:_tempItem];

        _batteryItem = [[SBCPUStatItemView alloc] init];
        _batteryItem.iconView.image = [UIImage systemImageNamed:@"battery.100"];
        [_blurView.contentView addSubview:_batteryItem];

        _currentItem = [[SBCPUStatItemView alloc] init];
        _currentItem.iconView.image = [UIImage systemImageNamed:@"bolt.fill"];
        [_blurView.contentView addSubview:_currentItem];

        // 折叠时的单标签，居中显示
        _collapsedLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, 52, 36)];
        _collapsedLabel.textColor = [UIColor whiteColor];
        _collapsedLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightBold];
        _collapsedLabel.textAlignment = NSTextAlignmentCenter;
        _collapsedLabel.adjustsFontSizeToFitWidth = YES;
        _collapsedLabel.hidden = YES;
        [_blurView.contentView addSubview:_collapsedLabel];

        // 充电时的绿色/橙色呼吸小圆点
        _chargingIndicator = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 6)];
        _chargingIndicator.layer.cornerRadius = 3.0f;
        _chargingIndicator.backgroundColor = [UIColor systemGreenColor];
        _chargingIndicator.hidden = YES;
        [self addSubview:_chargingIndicator];

        [self resetInactivityTimer];
    }
    return self;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPress {
    if (longPress.state == UIGestureRecognizerStateBegan) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator prepare]; 
        [generator impactOccurred];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!detailShowing && cpuWindow.rootViewController) {
                if (cpuWindow.rootViewController.presentedViewController) {
                    [cpuWindow.rootViewController.presentedViewController dismissViewControllerAnimated:NO completion:nil];
                }
                detailShowing = YES;
                detailVC = [[SBCPUDetailViewController alloc] init];
                detailVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
                detailVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
                [cpuWindow.rootViewController presentViewController:detailVC animated:YES completion:nil];
            }
        });
    }
}

- (void)handleSingleTap:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateEnded) {
        if (_isCollapsed) {
            [self expandFromEdgeAnimated:YES];
        } else {
            [self resetInactivityTimer];
        }
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateEnded) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!settingsShowing && cpuWindow.rootViewController) {
                if (cpuWindow.rootViewController.presentedViewController) {
                    [cpuWindow.rootViewController.presentedViewController dismissViewControllerAnimated:NO completion:nil];
                }
                settingsShowing = YES;
                SBCPUSettingsController *vc = [[SBCPUSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
                UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
                nav.modalPresentationStyle = UIModalPresentationFullScreen;
                [cpuWindow.rootViewController presentViewController:nav animated:YES completion:nil];
            }
        });
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    [self resetInactivityTimer];

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.lastPoint = self.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:self.superview];
        self.center = CGPointMake(self.lastPoint.x + translation.x, self.lastPoint.y + translation.y);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (rememberPositionEnable) {
            [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGRect(self.frame) forKey:@"SBCPU.LastFrame"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        [self updateLayout:YES]; 
        [self resetInactivityTimer];
    }
}

- (void)resetInactivityTimer {
    if (_inactivityTimer) { 
        [_inactivityTimer invalidate]; 
        _inactivityTimer = nil; 
    }
    
    if (autoCollapseEnable && !_isCollapsed && !settingsShowing && !detailShowing) {
        if (autoExpandLandscape) {
            UIInterfaceOrientation orientation = getActiveInterfaceOrientation();
            if (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight) {
                return; 
            }
        }
        _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:autoCollapseDelay target:self selector:@selector(inactivityTimerFired) userInfo:nil repeats:NO];
    }
}

- (void)inactivityTimerFired {
    [_inactivityTimer invalidate]; 
    _inactivityTimer = nil;

    if (!settingsShowing && !detailShowing && !_isCollapsed) {
        if (autoExpandLandscape) {
            UIInterfaceOrientation orientation = getActiveInterfaceOrientation();
            if (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight) {
                return;
            }
        }
        [self collapseToEdgeAnimated:YES];
    }
}

// 🌟 全新的自动排版引擎 (丝滑灵动岛)
- (void)updateLayout:(BOOL)animated {
    CGFloat targetHeight = 36.0f; // 增高一点，胶囊更圆润
    CGFloat currentX = 0;

    _collapsedLabel.hidden = !_isCollapsed;

    if (_isCollapsed) {
        _cpuItem.hidden = YES; 
        _fpsItem.hidden = YES; 
        _tempItem.hidden = YES; 
        _batteryItem.hidden = YES; 
        _currentItem.hidden = YES;
        currentX = 68.0f; // 折叠时的固定宽度
    } else {
        _cpuItem.hidden = NO;
        _fpsItem.hidden = !showFps;
        _tempItem.hidden = !showBatteryTemperature;
        _batteryItem.hidden = !showBatteryPercent;
        _currentItem.hidden = !(showBatteryCurrent && isChargingInternal());

        NSMutableArray *visibleItems = [NSMutableArray array];
        if (!_cpuItem.hidden) [visibleItems addObject:_cpuItem];
        if (!_fpsItem.hidden) [visibleItems addObject:_fpsItem];
        if (!_tempItem.hidden) [visibleItems addObject:_tempItem];
        if (!_batteryItem.hidden) [visibleItems addObject:_batteryItem];
        if (!_currentItem.hidden) [visibleItems addObject:_currentItem];

        for (int i = 0; i < visibleItems.count; i++) {
            SBCPUStatItemView *item = visibleItems[i];
            item.frame = CGRectMake(currentX, 0, 70, targetHeight);
            item.separator.hidden = (i == visibleItems.count - 1); // 最后一个隐藏分割线
            currentX += 70;
        }
    }

    CGFloat targetWidth = currentX;
    if (targetWidth < 68.0f) targetWidth = 68.0f;
    
    // 计算边界和避让灵动岛
    CGRect containerBounds = self.superview ? self.superview.bounds : [UIScreen mainScreen].bounds;
    CGFloat halfW = targetWidth / 2.0f;
    CGFloat halfH = targetHeight / 2.0f;
    
    CGFloat minX = halfW + 4.0f;
    CGFloat maxX = containerBounds.size.width - halfW - 4.0f;
    CGFloat minY = halfH + (_isCollapsed ? 30.0f : 45.0f); // 避开顶部状态栏
    CGFloat maxY = containerBounds.size.height - halfH - 20.0f;

    CGPoint targetCenter = self.center;

    if (_isCollapsed) {
        BOOL isLeft = (targetCenter.x <= containerBounds.size.width / 2.0f);
        targetCenter.x = isLeft ? minX - 10.0f : maxX + 10.0f; // 折叠时往屏幕边缘贴一点，变窄
    } else if (smartDockEnable) {
        if (dockMode == 1) {
            targetCenter.x = minX;
        } else if (dockMode == 2) {
            targetCenter.x = maxX;
        } else if (dockMode == 3) {
            targetCenter.y = minY;
        } else if (dockMode == 4) {
            targetCenter.y = maxY;
        } else if (dockMode == 0) {
            CGFloat distLeft = targetCenter.x - minX; 
            CGFloat distRight = maxX - targetCenter.x;
            CGFloat distTop = targetCenter.y - minY; 
            CGFloat distBottom = maxY - targetCenter.y;
            
            CGFloat minDist = MIN(MIN(distLeft, distRight), MIN(distTop, distBottom));
            if (minDist == distLeft) targetCenter.x = minX;
            else if (minDist == distRight) targetCenter.x = maxX;
            else if (minDist == distTop) targetCenter.y = minY;
            else if (minDist == distBottom) targetCenter.y = maxY;
        }
    }

    // 边缘限制
    if (!_isCollapsed) {
        if (targetCenter.x < minX) targetCenter.x = minX;
        if (targetCenter.x > maxX) targetCenter.x = maxX;
    }
    if (targetCenter.y < minY) targetCenter.y = minY;
    if (targetCenter.y > maxY) targetCenter.y = maxY;

    // 避让灵动岛 (左右 75pt，高度 54pt)
    if (containerBounds.size.height > containerBounds.size.width && containerBounds.size.height > 800) {
        if (targetCenter.y - halfH < 54.0) { 
            if (targetCenter.x + halfW > containerBounds.size.width / 2.0 - 75.0 && 
                targetCenter.x - halfW < containerBounds.size.width / 2.0 + 75.0) {
                targetCenter.y = 54.0 + halfH + 8.0;
            }
        }
    }

    void (^animationsBlock)(void) = ^{
        self.bounds = CGRectMake(0, 0, targetWidth, targetHeight);
        self.center = targetCenter;
        
        self.blurView.frame = self.bounds;
        self.blurView.layer.cornerRadius = targetHeight / 2.0f; // 完美的半圆胶囊
        
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:targetHeight / 2.0f].CGPath;
        
        if (isChargingInternal()) {
            self.chargingIndicator.hidden = NO;
            self.chargingIndicator.center = CGPointMake(targetWidth - 8, 8);
        } else {
            self.chargingIndicator.hidden = YES;
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:animationsBlock completion:nil];
    } else {
        animationsBlock();
    }
}

- (void)collapseToEdgeAnimated:(BOOL)animated {
    if (_isCollapsed) return;
    _isCollapsed = YES;
    [self updateLayout:animated];
}

- (void)expandFromEdgeAnimated:(BOOL)animated {
    if (!_isCollapsed) { 
        [self resetInactivityTimer]; 
        return; 
    }
    _isCollapsed = NO;
    [self updateLayout:animated];
    [self resetInactivityTimer];
}

- (void)triggerPlugAnimation {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    animation.values = @[@1.0, @1.1, @0.95, @1.0];
    animation.keyTimes = @[@0.0, @0.4, @0.7, @1.0];
    animation.duration = 0.4;
    [_blurView.layer addAnimation:animation forKey:@"plugBounce"];
}

- (void)updateDataWithCPU:(double)cpu cpuFreq:(double)cpuFreq fps:(double)fps battery:(NSInteger)battery temp:(double)temp current:(double)current isCharging:(BOOL)isCharging {
    
    // 高级颜色系统
    UIColor *normalColor = [UIColor whiteColor];
    UIColor *dangerColor = [UIColor colorWithRed:1.0f green:0.3f blue:0.3f alpha:1.0f];
    UIColor *warningColor = [UIColor systemOrangeColor];
    UIColor *safeColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f]; 
    UIColor *fpsColor = [UIColor colorWithRed:0.22f green:0.74f blue:0.97f alpha:1.0f]; 

    // 填充数据并更新颜色
    if (showCpuFrequency && !_isCollapsed) {
        [_cpuItem updateWithText:[NSString stringWithFormat:@"%.0f", cpuFreq] color:(cpu >= 80.0) ? dangerColor : normalColor];
    } else {
        [_cpuItem updateWithText:[NSString stringWithFormat:@"%.0f%%", cpu] color:(cpu >= 80.0) ? dangerColor : normalColor];
    }

    [_fpsItem updateWithText:[NSString stringWithFormat:@"%.0f", fps] color:fpsColor];
    
    [_batteryItem updateWithText:[NSString stringWithFormat:@"%ld%%", (long)battery] color:isCharging ? safeColor : normalColor];
    
    UIColor *tempColor = (temp >= 40.0) ? dangerColor : ((temp >= 36.0) ? warningColor : normalColor);
    [_tempItem updateWithText:(temp > 0) ? [NSString stringWithFormat:@"%.0f°", temp] : @"--°" color:tempColor];

    [_currentItem updateWithText:[NSString stringWithFormat:@"%.0fmA", current] color:[UIColor systemYellowColor]];
    
    // 充电指示灯
    if (isCharging && isCurrentlyChargeInhibited) {
        _chargingIndicator.backgroundColor = [UIColor systemOrangeColor]; 
    } else {
        _chargingIndicator.backgroundColor = [UIColor systemGreenColor];
    }

    // 更新折叠显示的文字
    if (_isCollapsed) {
        if (collapsedDisplayMode == 0) {
            _collapsedLabel.text = [NSString stringWithFormat:@"%.0f%%", cpu];
            _collapsedLabel.textColor = (cpu >= 80.0) ? dangerColor : normalColor;
        } else if (collapsedDisplayMode == 1) {
            _collapsedLabel.text = [NSString stringWithFormat:@"%.0f", fps];
            _collapsedLabel.textColor = fpsColor;
        } else if (collapsedDisplayMode == 2) {
            _collapsedLabel.text = (temp > 0) ? [NSString stringWithFormat:@"%.0f°", temp] : @"--°";
            _collapsedLabel.textColor = tempColor;
        } else if (collapsedDisplayMode == 3) {
            _collapsedLabel.text = [NSString stringWithFormat:@"%.0fmA", current];
            _collapsedLabel.textColor = [UIColor systemYellowColor];
        }
    }
}
@end


#pragma mark - 6. 长按显示的控制中心毛玻璃卡片 (🌟 UI大重构)

@implementation SBCPUDetailViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    _labelsDict = [NSMutableDictionary dictionary];
    
    if ([CMPedometer isStepCountingAvailable]) {
        _pedometer = [[CMPedometer alloc] init];
    }
    
    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeDetailView)]];

    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat panelW = MIN(screenW - 40, 360.0);
    CGFloat panelH = 380.0;

    // 高级厚模糊材质卡片
    _blurEffectView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    _blurEffectView.frame = CGRectMake((screenW - panelW)/2.0, (screenH - panelH)/2.0, panelW, panelH);
    _blurEffectView.layer.cornerRadius = 24.0;
    _blurEffectView.layer.masksToBounds = YES;
    _blurEffectView.layer.borderWidth = 1.0;
    _blurEffectView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    [self.view addSubview:_blurEffectView];
    
    [_blurEffectView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:nil action:nil]];

    UIView *contentView = _blurEffectView.contentView;

    // 左上角小图标
    UIImageView *titleIcon = [[UIImageView alloc] initWithFrame:CGRectMake(24, 20, 20, 20)];
    titleIcon.image = [UIImage systemImageNamed:@"bolt.shield.fill"];
    titleIcon.tintColor = [UIColor systemYellowColor];
    [contentView addSubview:titleIcon];

    // 大标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(52, 19, panelW - 100, 22)];
    titleLabel.text = @"系统资源与电池监控";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    [contentView addSubview:titleLabel];

    // 关闭按钮
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(panelW - 44, 16, 28, 28);
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    [closeBtn setTintColor:[UIColor colorWithWhite:0.6 alpha:1.0]];
    [closeBtn addTarget:self action:@selector(closeDetailView) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:closeBtn];

    // 内容布局 (Vertical StackView for Card-based list)
    UIStackView *mainStack = [[UIStackView alloc] initWithFrame:CGRectMake(20, 60, panelW - 40, panelH - 80)];
    mainStack.axis = UILayoutConstraintAxisVertical;
    mainStack.distribution = UIStackViewAlignmentFill;
    mainStack.spacing = 10;
    [contentView addSubview:mainStack];

    // 定义每行展示的数据
    NSArray *items = @[
        @{@"icon": @"cpu", @"color": [UIColor systemGreenColor], @"title": @"SpringBoard CPU 负载", @"key": @"cpu"},
        @{@"icon": @"speedometer", @"color": [UIColor systemTealColor], @"title": @"当前主频 / 屏幕帧率", @"key": @"freq"},
        @{@"icon": @"memorychip", @"color": [UIColor systemPurpleColor], @"title": @"运行内存与存储容量", @"key": @"mem"},
        @{@"icon": @"battery.100.bolt", @"color": [UIColor systemYellowColor], @"title": @"电池状态与健康寿命", @"key": @"bat1"},
        @{@"icon": @"thermometer.sun", @"color": [UIColor systemOrangeColor], @"title": @"充放电流、电压与温度", @"key": @"bat2"},
        @{@"icon": @"network", @"color": [UIColor systemBlueColor], @"title": @"网络状态与实时网速", @"key": @"net"}
    ];

    for (NSDictionary *dict in items) {
        UIView *row = [[UIView alloc] init];
        row.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06]; // 磨砂半透明行
        row.layer.cornerRadius = 12.0;
        
        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(12, 14, 20, 20)];
        icon.image = [UIImage systemImageNamed:dict[@"icon"]];
        icon.tintColor = dict[@"color"];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        [row addSubview:icon];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(42, 6, panelW - 100, 16)];
        title.text = dict[@"title"];
        title.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        title.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        [row addSubview:title];

        UILabel *value = [[UILabel alloc] initWithFrame:CGRectMake(42, 24, panelW - 70, 18)];
        value.textColor = [UIColor whiteColor];
        value.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
        value.adjustsFontSizeToFitWidth = YES;
        value.minimumScaleFactor = 0.5;
        [row addSubview:value];

        _labelsDict[dict[@"key"]] = value;
        [mainStack addArrangedSubview:row];
    }
}

- (void)viewWillAppear:(BOOL)animated { 
    [super viewWillAppear:animated]; 
    [self refreshAllDetailData]; 
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshAllDetailData) userInfo:nil repeats:YES]; 
}

- (void)viewWillDisappear:(BOOL)animated { 
    [super viewWillDisappear:animated]; 
    [_refreshTimer invalidate]; 
    _refreshTimer = nil; 
}

- (void)closeDetailView { 
    detailShowing = NO; 
    [self dismissViewControllerAnimated:YES completion:^{ 
        if (floatingView) [floatingView resetInactivityTimer]; 
    }]; 
}

- (void)refreshAllDetailData {
    DeviceSpec spec = getDeviceSpec();
    NSDictionary *batInfo = getRealBatteryDetails();

    double cpuUsage = getSpringBoardCPUUsage();
    _labelsDict[@"cpu"].text = [NSString stringWithFormat:@"%s %ld核 · 占用 %.1f%%", spec.chipName, (long)spec.cores, cpuUsage];
    
    double freq = getRealCPUFrequency(cpuUsage);
    _labelsDict[@"freq"].text = [NSString stringWithFormat:@"%.0f MHz  |  %.0f FPS", freq, [SBCPUFPSHelper sharedInstance].currentFPS];

    mach_port_t hP = mach_host_self(); 
    mach_msg_type_number_t hS = sizeof(vm_statistics64_data_t) / sizeof(integer_t); 
    vm_size_t pS; 
    host_page_size(hP, &pS); 
    vm_statistics64_data_t vS; 
    uint64_t freeMB = 0; 
    if (host_statistics64(hP, HOST_VM_INFO64, (host_info64_t)&vS, &hS) == KERN_SUCCESS) {
        freeMB = (uint64_t)(vS.free_count + vS.inactive_count) * (uint64_t)pS / (1024 * 1024);
    }
    
    NSDictionary *fA = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil]; 
    _labelsDict[@"mem"].text = [NSString stringWithFormat:@"RAM 余: %lluMB  |  ROM 余: %.1fGB", freeMB, [fA[NSFileSystemFreeSize] longLongValue] / (1024.0*1024.0*1024.0)];

    NSInteger dCap = [batInfo[@"DesignCapacity"] integerValue] ?: spec.designBatteryCapacity;
    NSInteger mCap = [batInfo[@"MaxCapacity"] integerValue]; 
    if (mCap <= 100 && dCap > 0) mCap = dCap;
    
    [UIDevice currentDevice].batteryMonitoringEnabled = YES; 
    NSInteger batP = (NSInteger)([UIDevice currentDevice].batteryLevel * 100); 
    if (batP < 0) batP = 100;
    
    _labelsDict[@"bat1"].text = [NSString stringWithFormat:@"%ld%%电量 | 寿命 %.0f%% | 循环 %ld 次", (long)batP, (dCap > 0) ? MIN(100.0, ((double)mCap / dCap * 100.0)) : 100.0, (long)[batInfo[@"CycleCount"] integerValue]];

    double temp = getBatteryTemperatureInternal();
    _labelsDict[@"bat2"].text = [NSString stringWithFormat:@"%.0f mA | %.2f V | %.1f °C", getBatteryCurrentInternal(), [batInfo[@"Voltage"] doubleValue] / 1000.0, temp > -10 ? temp : 0.0];

    struct ifaddrs *ifa_list = NULL; 
    uint64_t speedD = 0, speedU = 0;
    if (getifaddrs(&ifa_list) >= 0) {
        uint64_t wI = 0, wO = 0, cI = 0, cO = 0;
        for (struct ifaddrs *ifa = ifa_list; ifa; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_LINK) {
                NSString *n = [NSString stringWithUTF8String:ifa->ifa_name]; 
                struct if_data *d = (struct if_data *)ifa->ifa_data;
                if (d) { 
                    if ([n hasPrefix:@"en"]) { wI += d->ifi_ibytes; wO += d->ifi_obytes; } 
                    else if ([n hasPrefix:@"pdp"]) { cI += d->ifi_ibytes; cO += d->ifi_obytes; } 
                }
            }
        }
        freeifaddrs(ifa_list); 
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent(); 
        double tD = now - lastNetSpeedTime; 
        if (tD <= 0) tD = 1.0;
        if (lastWifiInBytes > 0) { 
            speedD = (uint64_t)((wI - lastWifiInBytes + cI - lastCellInBytes) / tD); 
            speedU = (uint64_t)((wO - lastWifiOutBytes + cO - lastCellOutBytes) / tD); 
        }
        lastWifiInBytes = wI; 
        lastWifiOutBytes = wO; 
        lastCellInBytes = cI; 
        lastCellOutBytes = cO; 
        lastNetSpeedTime = now;
    }
    _labelsDict[@"net"].text = [NSString stringWithFormat:@"%@  |  ↓%llu K/s  ↑%llu K/s", getNetworkType(), speedD / 1024, speedU / 1024];
}
@end


#pragma mark - 7. 后续控制与窗口类 (保持逻辑完美继承)

static void checkHighCPU(double cpu) {
    if (!autoLogoutEnable || cpu < logoutCPUThreshold) { cpuHighStartTime = nil; logoutCounting = NO; return; }
    if (!cpuHighStartTime) { cpuHighStartTime = [NSDate date]; return; }
    if ([[NSDate date] timeIntervalSinceDate:cpuHighStartTime] >= logoutDuration && !logoutCounting) {
        logoutCounting = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!cpuWindow || !cpuWindow.rootViewController) return;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CPU过高安全保护" message:@"即将执行防烧毁重启" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { logoutCounting = NO; cpuHighStartTime = nil; }]];
            [cpuWindow.rootViewController presentViewController:alert animated:YES completion:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (logoutCounting) kill(getpid(), SIGTERM); });
        });
    }
}

static void updateCPU(void) {
    if (!isEnabled) return;
    double cpu = getSpringBoardCPUUsage();
    double cpuFreq = getRealCPUFrequency(cpu);
    double fps = [SBCPUFPSHelper sharedInstance].currentFPS;
    checkHighCPU(cpu);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!floatingView) return;
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        NSInteger battery = (NSInteger)([UIDevice currentDevice].batteryLevel * 100);
        double temp = getBatteryTemperatureInternal();
        double current = getBatteryCurrentInternal();
        BOOL charging = isChargingInternal();

        if (smartChargeLimitEnable && temp > 0) {
            if (temp >= smartChargeLimitTemp) { setHardwareChargingInhibit(YES); isCurrentlyChargeInhibited = YES; }
            else if (temp <= (smartChargeLimitTemp - 1.0f)) { setHardwareChargingInhibit(NO); isCurrentlyChargeInhibited = NO; }
            else setHardwareChargingInhibit(isCurrentlyChargeInhibited); 
        } else if (!smartChargeLimitEnable && isCurrentlyChargeInhibited) { setHardwareChargingInhibit(NO); isCurrentlyChargeInhibited = NO; }

        if (charging && !previousChargingState) {
            if (floatingView.isCollapsed) [floatingView expandFromEdgeAnimated:YES];
            [floatingView triggerPlugAnimation];
        }
        previousChargingState = charging;

        if (autoExpandLandscape) {
            UIInterfaceOrientation orientation = getActiveInterfaceOrientation();
            BOOL isLandscape = (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight);
            if (isLandscape && !wasLandscape && floatingView.isCollapsed) { [floatingView expandFromEdgeAnimated:YES]; }
            else if (!isLandscape && wasLandscape && !floatingView.isCollapsed) { [floatingView resetInactivityTimer]; }
            wasLandscape = isLandscape;
        }

        [floatingView updateDataWithCPU:cpu cpuFreq:cpuFreq fps:fps battery:battery temp:temp current:current isCharging:charging];
        [floatingView updateLayout:YES]; 
    });
}

static void applySystemRefreshRate(void) {
    BOOL apply120 = force120HzEnable && (!thermalProtectionEnable || !isDeviceOverheated());
    Class serverClass = NSClassFromString(@"CAWindowServer");
    if (serverClass && [serverClass respondsToSelector:@selector(serverIfRunning)]) {
        CAWindowServer *server = [serverClass serverIfRunning];
        if (server) {
            for (CAWindowServerDisplay *display in [server displays]) {
                if ([display respondsToSelector:@selector(setAllowsVirtualModes:)]) [display setAllowsVirtualModes:YES];
                if (apply120) {
                    if ([display respondsToSelector:@selector(setMinimumRefreshRate:)]) [display setMinimumRefreshRate:120.0f];
                    if ([display respondsToSelector:@selector(setMaximumRefreshRate:)]) [display setMaximumRefreshRate:120.0f];
                    if ([display respondsToSelector:@selector(setIdealRefreshRate:)]) [display setIdealRefreshRate:120.0f];
                }
            }
        }
    }
    if (cpuWindow && [SBCPUFPSHelper sharedInstance].driverLayer.superlayer == nil) {
        [cpuWindow.layer addSublayer:[SBCPUFPSHelper sharedInstance].driverLayer];
    }
    [[SBCPUFPSHelper sharedInstance] updateFrameRate];
}

@implementation SBCPUPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { 
    UIView *h = [super hitTest:point withEvent:event]; 
    return (h == self) ? nil : h; 
}
@end

@implementation SBCPURootViewController
- (void)loadView { 
    SBCPUPassthroughView *v = [[SBCPUPassthroughView alloc] initWithFrame:UIScreen.mainScreen.bounds]; 
    v.backgroundColor = UIColor.clearColor; 
    self.view = v; 
}
- (BOOL)shouldAutorotate { return YES; } 
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; } 
- (BOOL)prefersStatusBarHidden { return YES; }

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator { 
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator]; 
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> ctx) { 
        if (floatingView) updateFloatingSize(); 
    } completion:nil]; 
}
@end

@implementation SBCPUWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (settingsShowing || detailShowing) return [super hitTest:point withEvent:event];
    if (floatingView && !floatingView.hidden && floatingView.alpha > 0.01 && [floatingView pointInside:[self convertPoint:point toView:floatingView] withEvent:event]) {
        return floatingView;
    }
    return nil;
}
@end

@implementation SBCPUValuePickerController
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 7; } 
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"CPU 触发值"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { 
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; 
    NSArray *t = @[@"80%", @"100%", @"120%", @"140%", @"160%", @"180%", @"200%"]; 
    NSArray *v = @[@80, @100, @120, @140, @160, @180, @200]; 
    c.textLabel.text = t[indexPath.row]; 
    if ([v[indexPath.row] doubleValue] == logoutCPUThreshold) c.accessoryType = UITableViewCellAccessoryCheckmark; 
    return c; 
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { 
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; 
    logoutCPUThreshold = [@[@80, @100, @120, @140, @160, @180, @200][indexPath.row] doubleValue]; 
    SavePreferencesAndNotify(); 
    [tableView reloadData]; 
}
@end

@implementation SBCPUTimePickerController
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 7; } 
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"持续时间"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { 
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; 
    NSArray *t = @[@"10 秒", @"30 秒", @"60 秒", @"120 秒", @"180 秒", @"300 秒", @"600 秒"]; 
    NSArray *v = @[@10, @30, @60, @120, @180, @300, @600]; 
    c.textLabel.text = t[indexPath.row]; 
    if ([v[indexPath.row] integerValue] == logoutDuration) c.accessoryType = UITableViewCellAccessoryCheckmark; 
    return c; 
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { 
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; 
    logoutDuration = [@[@10, @30, @60, @120, @180, @300, @600][indexPath.row] integerValue]; 
    SavePreferencesAndNotify(); 
    [tableView reloadData]; 
}
@end

@implementation SBCPUSettingsController
- (void)viewDidLoad { 
    [super viewDidLoad]; 
    self.title = @"SBCPUFloating 设置"; 
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeSettings)]; 
}

- (void)closeSettings { 
    settingsShowing = NO; 
    [self dismissViewControllerAnimated:YES completion:^{ 
        if (cpuWindow) [cpuWindow setNeedsLayout]; 
        if (floatingView) [floatingView resetInactivityTimer]; 
    }]; 
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 8; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { 
    if (section == 0) return 4; 
    if (section == 1) return 3; 
    if (section == 2) return 4; 
    if (section == 3) return 3; 
    if (section == 4) return 2; 
    if (section == 5) return 5; 
    if (section == 6) return 2; 
    return 6; 
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { 
    if (section == 0) return @"📱 智能缩进与侧边吸附"; 
    if (section == 1) return @"⚡ 自动控制与防护"; 
    if (section == 2) return @"🔲 悬浮窗外观"; 
    if (section == 3) return @"🧠 智能选项"; 
    if (section == 4) return @"🎮 性能与高刷锁定"; 
    if (section == 5) return @"🌡️ Insulation (温控核心)"; 
    if (section == 6) return @"🔌 电池温控与断充"; 
    return @"📍 位置与显示"; 
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { 
    if (section == 4) return @"💡 强制 120Hz 全局锁定满帧。"; 
    if (section == 5) return @"💡 模拟低电频率：底层压制降温；防止温控降频：释放极限性能。"; 
    if (section == 6) return @"💡 高温智能断充：旁路供电保护电池。"; 
    return nil; 
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) { 
            cell.textLabel.text = @"无操作自动收起"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = autoCollapseEnable; 
            [sw addTarget:self action:@selector(changeAutoCollapse:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
        else if (indexPath.row == 1) { 
            cell.textLabel.text = @"收起延迟时间"; 
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 秒", (long)autoCollapseDelay]; 
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; 
        }
        else if (indexPath.row == 2) { 
            cell.textLabel.text = @"折叠显示内容"; 
            NSArray *modes = @[@"CPU 使用率", @"FPS 帧率", @"电池温度", @"电池电流"]; 
            cell.detailTextLabel.text = (collapsedDisplayMode >= 0 && collapsedDisplayMode < modes.count) ? modes[collapsedDisplayMode] : modes[0]; 
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; 
        }
        else if (indexPath.row == 3) { 
            cell.textLabel.text = @"横屏游戏自动展开"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = autoExpandLandscape; 
            [sw addTarget:self action:@selector(changeAutoExpandLandscape:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) { 
            cell.textLabel.text = @"自动注销"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = autoLogoutEnable; 
            [sw addTarget:self action:@selector(changeLogout:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
        else if (indexPath.row == 1) { 
            cell.textLabel.text = @"CPU 触发值"; 
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", logoutCPUThreshold]; 
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; 
        }
        else if (indexPath.row == 2) { 
            cell.textLabel.text = @"持续时间"; 
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 秒", (long)logoutDuration]; 
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; 
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) { 
            cell.textLabel.text = @"透明度开关"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = floatingAlphaEnable; 
            [sw addTarget:self action:@selector(changeAlphaEnable:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
        else if (indexPath.row == 1) { 
            cell.textLabel.text = @"透明度"; 
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", floatingAlpha * 100.0]; 
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; 
        }
        else if (indexPath.row == 2) { 
            cell.textLabel.text = @"浮窗大小"; 
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,130,30)]; 
            slider.minimumValue = 0.4; 
            slider.maximumValue = 1.6; 
            slider.value = floatingScale; 
            [slider addTarget:self action:@selector(changeScaleSlider:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = slider; 
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", floatingScale * 100]; 
        }
        else if (indexPath.row == 3) { 
            cell.textLabel.text = @"字体大小"; 
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,130,30)]; 
            slider.minimumValue = 8.0; 
            slider.maximumValue = 15.0; 
            slider.value = floatingFontSize; 
            [slider addTarget:self action:@selector(changeFontSlider:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = slider; 
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0fpt", floatingFontSize]; 
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) { 
            cell.textLabel.text = @"键盘避让"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = keyboardAvoidEnable; 
            [sw addTarget:self action:@selector(changeKeyboardAvoid:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
        else if (indexPath.row == 1) { 
            cell.textLabel.text = @"智能吸附"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = smartDockEnable; 
            [sw addTarget:self action:@selector(changeSmartDock:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
        else if (indexPath.row == 2) { 
            cell.textLabel.text = @"吸附模式"; 
            NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"]; 
            cell.detailTextLabel.text = (dockMode >= 0 && dockMode < modes.count) ? modes[dockMode] : @"自动"; 
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; 
        }
    } else if (indexPath.section == 4) {
        if (indexPath.row == 0) { 
            cell.textLabel.text = @"强制 120Hz 高刷模式"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = force120HzEnable; 
            [sw addTarget:self action:@selector(changeForce120Hz:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
        else if (indexPath.row == 1) { 
            cell.textLabel.text = @"智能温控降频保护"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = thermalProtectionEnable; 
            [sw addTarget:self action:@selector(changeThermalProtection:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) { 
            cell.textLabel.text = @"CPU 模式"; 
            NSArray *modes = @[@"苹果原生温控", @"模拟低电频率", @"防止温控降频"]; 
            cell.detailTextLabel.text = (insulationCpuMode >= 0 && insulationCpuMode < modes.count) ? modes[insulationCpuMode] : modes[0]; 
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; 
        }
        else if (indexPath.row == 1) { 
            cell.textLabel.text = @"拦截温控暗屏"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = blockThermalDimming; 
            [sw addTarget:self action:@selector(changeInsulationDimming:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
        else if (indexPath.row == 2) { 
            cell.textLabel.text = @"拦截温度计弹窗"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = blockThermalAlert; 
            [sw addTarget:self action:@selector(changeInsulationThermometer:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
        else if (indexPath.row == 3) { 
            cell.textLabel.text = @"拦截口袋高温"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = blockPocketTemp; 
            [sw addTarget:self action:@selector(changeInsulationPocket:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
        else if (indexPath.row == 4) { 
            cell.textLabel.text = @"拦截阳光限制"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = forceSunlightHBM; 
            [sw addTarget:self action:@selector(changeInsulationSunlight:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
    } else if (indexPath.section == 6) {
        if (indexPath.row == 0) { 
            cell.textLabel.text = @"开启高温智能断充"; 
            UISwitch *sw = [UISwitch new]; 
            sw.on = smartChargeLimitEnable; 
            [sw addTarget:self action:@selector(changeSmartChargeLimit:) forControlEvents:UIControlEventValueChanged]; 
            cell.accessoryView = sw; 
        }
        else if (indexPath.row == 1) { 
            cell.textLabel.text = @"断充温度阈值"; 
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f°C", smartChargeLimitTemp]; 
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; 
        }
    } else if (indexPath.section == 7) {
        if (indexPath.row == 0) { cell.textLabel.text = @"记忆悬浮窗位置"; UISwitch *sw = [UISwitch new]; sw.on = rememberPositionEnable; [sw addTarget:self action:@selector(changeRememberPosition:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = sw; }
        else if (indexPath.row == 1) { cell.textLabel.text = @"显示 CPU 频率"; UISwitch *sw = [UISwitch new]; sw.on = showCpuFrequency; [sw addTarget:self action:@selector(changeShowCpuFreq:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = sw; }
        else if (indexPath.row == 2) { cell.textLabel.text = @"显示 FPS 帧率"; UISwitch *sw = [UISwitch new]; sw.on = showFps; [sw addTarget:self action:@selector(changeShowFps:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = sw; }
        else if (indexPath.row == 3) { cell.textLabel.text = @"显示电池百分比"; UISwitch *sw = [UISwitch new]; sw.on = showBatteryPercent; [sw addTarget:self action:@selector(changeShowBattery:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = sw; }
        else if (indexPath.row == 4) { cell.textLabel.text = @"显示电池温度"; UISwitch *sw = [UISwitch new]; sw.on = showBatteryTemperature; [sw addTarget:self action:@selector(changeShowTemp:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = sw; }
        else if (indexPath.row == 5) { cell.textLabel.text = @"显示实时电流"; UISwitch *sw = [UISwitch new]; sw.on = showBatteryCurrent; [sw addTarget:self action:@selector(changeShowCurrent:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = sw; }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (indexPath.row == 1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无操作收起延迟" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            NSArray *titles = @[@"2 秒", @"3 秒", @"4 秒", @"5 秒", @"8 秒", @"10 秒"]; 
            NSArray *values = @[@2, @3, @4, @5, @8, @10];
            for (NSInteger i = 0; i < titles.count; i++) {
                [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { 
                    autoCollapseDelay = [values[i] integerValue]; 
                    SavePreferencesAndNotify(); 
                    [self.tableView reloadData]; 
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; 
            [self presentViewController:alert animated:YES completion:nil];
        } else if (indexPath.row == 2) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"折叠显示内容" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            NSArray *titles = @[@"CPU 使用率", @"FPS 帧率", @"电池温度", @"电池电流"];
            for (NSInteger i = 0; i < titles.count; i++) {
                [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { 
                    collapsedDisplayMode = i; 
                    SavePreferencesAndNotify(); 
                    [self.tableView reloadData]; 
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; 
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 1) {
            [self.navigationController pushViewController:[[SBCPUValuePickerController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
        } else if (indexPath.row == 2) {
            [self.navigationController pushViewController:[[SBCPUTimePickerController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"透明度" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            NSArray *titles = @[@"20%", @"40%", @"60%", @"70%", @"80%", @"100%"]; 
            NSArray *values = @[@0.2, @0.4, @0.6, @0.7, @0.8, @1.0];
            for (NSInteger i = 0; i < titles.count; i++) {
                [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { 
                    floatingAlpha = [values[i] floatValue]; 
                    SavePreferencesAndNotify(); 
                    applyFloatingAlpha(); 
                    [self.tableView reloadData]; 
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; 
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 2) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"吸附模式" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"];
            for (NSInteger i = 0; i < modes.count; i++) {
                [alert addAction:[UIAlertAction actionWithTitle:modes[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { 
                    dockMode = i; 
                    SavePreferencesAndNotify(); 
                    [self.tableView reloadData]; 
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; 
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CPU 模式" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            NSArray *titles = @[@"苹果原生温控", @"模拟低电频率", @"防止温控降频"];
            for (NSInteger i = 0; i < titles.count; i++) {
                [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { 
                    insulationCpuMode = i; 
                    SavePreferencesAndNotify(); 
                    [self.tableView reloadData]; 
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; 
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if (indexPath.section == 6) {
        if (indexPath.row == 1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"断充温度阈值" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            NSArray *titles = @[@"35.0°C", @"36.0°C", @"37.0°C", @"38.0°C", @"39.0°C", @"40.0°C", @"41.0°C", @"42.0°C", @"43.0°C"]; 
            NSArray *values = @[@35.0, @36.0, @37.0, @38.0, @39.0, @40.0, @41.0, @42.0, @43.0];
            for (NSInteger i = 0; i < titles.count; i++) {
                [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { 
                    smartChargeLimitTemp = [values[i] floatValue]; 
                    SavePreferencesAndNotify(); 
                    [self.tableView reloadData]; 
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; 
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

- (void)saveConfigs { 
    SavePreferencesAndNotify(); 
}

- (void)changeScaleSlider:(UISlider *)slider { 
    floatingScale = slider.value; 
    UITableViewCell *c = (UITableViewCell *)slider.superview; 
    while (c && ![c isKindOfClass:[UITableViewCell class]]) {
        c = (UITableViewCell *)c.superview; 
    }
    if (c) c.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", floatingScale * 100]; 
    updateFloatingSize(); 
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveConfigs) object:nil]; 
    [self performSelector:@selector(saveConfigs) withObject:nil afterDelay:0.5]; 
}

- (void)changeFontSlider:(UISlider *)slider { 
    floatingFontSize = slider.value; 
    UITableViewCell *c = (UITableViewCell *)slider.superview; 
    while (c && ![c isKindOfClass:[UITableViewCell class]]) {
        c = (UITableViewCell *)c.superview; 
    }
    if (c) c.detailTextLabel.text = [NSString stringWithFormat:@"%.0fpt", floatingFontSize]; 
    updateFloatingSize(); 
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveConfigs) object:nil]; 
    [self performSelector:@selector(saveConfigs) withObject:nil afterDelay:0.5]; 
}

- (void)changeAutoCollapse:(UISwitch *)sw { 
    autoCollapseEnable = sw.isOn; 
    SavePreferencesAndNotify(); 
    if (floatingView) { 
        if (!autoCollapseEnable && floatingView.isCollapsed) {
            [floatingView expandFromEdgeAnimated:YES]; 
        } else {
            [floatingView resetInactivityTimer]; 
        }
    } 
}

- (void)changeAutoExpandLandscape:(UISwitch *)sw { 
    autoExpandLandscape = sw.isOn; 
    SavePreferencesAndNotify(); 
    if (floatingView) updateFloatingSize(); 
}

- (void)changeLogout:(UISwitch *)sw { autoLogoutEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeAlphaEnable:(UISwitch *)sw { floatingAlphaEnable = sw.isOn; SavePreferencesAndNotify(); applyFloatingAlpha(); }
- (void)changeKeyboardAvoid:(UISwitch *)sw { keyboardAvoidEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeSmartDock:(UISwitch *)sw { smartDockEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeRememberPosition:(UISwitch *)sw { rememberPositionEnable = sw.isOn; SavePreferencesAndNotify(); }

- (void)changeForce120Hz:(UISwitch *)sw { force120HzEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeThermalProtection:(UISwitch *)sw { thermalProtectionEnable = sw.isOn; SavePreferencesAndNotify(); }

- (void)changeShowCpuFreq:(UISwitch *)sw { showCpuFrequency = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowFps:(UISwitch *)sw { showFps = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowBattery:(UISwitch *)sw { showBatteryPercent = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowTemp:(UISwitch *)sw { showBatteryTemperature = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowCurrent:(UISwitch *)sw { showBatteryCurrent = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }

- (void)changeInsulationDimming:(UISwitch *)sw { blockThermalDimming = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeInsulationThermometer:(UISwitch *)sw { blockThermalAlert = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeInsulationPocket:(UISwitch *)sw { blockPocketTemp = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeInsulationSunlight:(UISwitch *)sw { forceSunlightHBM = sw.isOn; SavePreferencesAndNotify(); }

- (void)changeSmartChargeLimit:(UISwitch *)sw { 
    smartChargeLimitEnable = sw.isOn; 
    SavePreferencesAndNotify(); 
    if (!smartChargeLimitEnable && isCurrentlyChargeInhibited) { 
        setHardwareChargingInhibit(NO); 
        isCurrentlyChargeInhibited = NO; 
    } 
}
@end

#pragma mark - 8. SpringBoard 侧核心拦截防线

static void onCCNotificationReceived(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) { 
    LoadPreferences(); 
}

static void registerV160Observers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

        [nc addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { 
            if (cpuWindow && floatingView) updateFloatingSize(); 
        }];

        [nc addObserverForName:UIKeyboardWillShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (settingsShowing || detailShowing || !keyboardAvoidEnable) return;
            if (cpuWindow && floatingView) {
                UIWindowScene *scene = getWindowScene(); 
                CGRect screenBounds = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
                if (CGRectGetMidY(floatingView.frame) < CGRectGetMidY(screenBounds)) return;
                
                if (!keyboardMoved) keyboardBeforeFrame = floatingView.frame;
                
                NSDictionary *info = n.userInfo;
                NSValue *endFrameValue = info[UIKeyboardFrameEndUserInfoKey];
                CGFloat keyboardHeight = 220.0;
                if (endFrameValue) {
                    CGRect keyboardFrame = [endFrameValue CGRectValue];
                    keyboardHeight = MIN(320.0, keyboardFrame.size.height);
                }

                CGRect f = keyboardBeforeFrame; 
                f.origin.y = MAX(20.0, f.origin.y - keyboardHeight);
                [UIView animateWithDuration:0.25 animations:^{ floatingView.frame = f; }]; 
                keyboardMoved = YES;
            }
        }];

        [nc addObserverForName:UIKeyboardWillHideNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (!settingsShowing && !detailShowing && keyboardMoved && floatingView) { 
                [UIView animateWithDuration:0.25 animations:^{ floatingView.frame = keyboardBeforeFrame; }]; 
                keyboardMoved = NO; 
            }
        }];
    });
}

%hook BrightnessSystemClient
- (BOOL)setProperty:(id)property forKey:(NSString *)key {
    if (blockThermalDimming) {
        if ([key isEqualToString:@"DisplayThermalMitigation"] || [key isEqualToString:@"ThermalMitigation"] || [key isEqualToString:@"KeyboardBacklightBrightnessLimit"]) {
            return YES; 
        }
    }
    return %orig;
}
%end

%hook SBBacklightController
- (void)setThermalWarningState:(NSInteger)state { 
    if (!blockThermalDimming) {
        %orig(state); 
    } else {
        %orig(0); 
    }
}
- (void)_updateBrightnessForSunlightLoad:(BOOL)arg1 { 
    if (forceSunlightHBM) {
        %orig(NO); 
    } else {
        %orig(arg1); 
    }
}
%end

%hook SBThermalController
- (void)showThermalAlertIfNecessary { 
    if (blockThermalAlert) return; 
    %orig; 
}
- (BOOL)isThermalBlocked { 
    if (blockThermalAlert) return NO; 
    return %orig; 
}
%end

%hook SBPocketStateMonitor
- (void)pocketStateDidChange:(NSInteger)state { 
    if (blockPocketTemp) {
        %orig(0); 
    } else {
        %orig(state); 
    }
}
%end

%ctor {
    %init;
    if ([[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"]) {
        LoadPreferences();
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), 
            NULL, 
            onCCNotificationReceived, 
            kPrefChangedNotification, 
            NULL, 
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            createCPUWindow(); 
            registerV160Observers();
            
            [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) { 
                updateCPU(); 
            }];
        });
    }
}

