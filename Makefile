
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SBCPUFloating SBCPUMitigation

# 1. 桌面 UI 与悬浮窗进程
SBCPUFloating_FILES = Tweak.xm
SBCPUFloating_CFLAGS = -fobjc-arc
SBCPUFloating_FRAMEWORKS = UIKit Foundation QuartzCore CoreMotion
SBCPUFloating_PRIVATE_FRAMEWORKS = PowerUI IOKit

# 2. 底层温控守护进程 (⚠️包含 IOKit 才能强写硬件)
SBCPUMitigation_FILES = MitigationHook.xm
SBCPUMitigation_CFLAGS = -fobjc-arc
SBCPUMitigation_FRAMEWORKS = Foundation
SBCPUMitigation_PRIVATE_FRAMEWORKS = IOKit

include $(THEOS_MAKE_PATH)/tweak.mk

# 注入桌面、温控、电源总控三大进程
INSTALL_TARGET_PROCESSES = SpringBoard thermalmonitord powerd

