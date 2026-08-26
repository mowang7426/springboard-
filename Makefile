
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

# 同时构建两个独立的 Tweak 动态库
TWEAK_NAME = SBCPUFloating SBCPUMitigation

# 1. SpringBoard 侧：UI、状态栏、手势与跨进程通知
SBCPUFloating_FILES = Tweak.xm
SBCPUFloating_CFLAGS = -fobjc-arc
SBCPUFloating_FRAMEWORKS = UIKit Foundation QuartzCore CoreMotion
SBCPUFloating_PRIVATE_FRAMEWORKS = PowerUI IOKit

# 2. thermalmonitord 侧：底层温控降频拦截与频点锁定
SBCPUMitigation_FILES = MitigationHook.xm
SBCPUMitigation_CFLAGS = -fobjc-arc
SBCPUMitigation_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

# 安装完成后自动重启相关守护进程
INSTALL_TARGET_PROCESSES = SpringBoard thermalmonitord


