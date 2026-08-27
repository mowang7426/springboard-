
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SBCPUFloating SBCPUMitigation

SBCPUFloating_FILES = Tweak.xm
SBCPUFloating_CFLAGS = -fobjc-arc
SBCPUFloating_FRAMEWORKS = UIKit Foundation QuartzCore CoreMotion
SBCPUFloating_PRIVATE_FRAMEWORKS = PowerUI IOKit

SBCPUMitigation_FILES = MitigationHook.xm
SBCPUMitigation_CFLAGS = -fobjc-arc
SBCPUMitigation_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

INSTALL_TARGET_PROCESSES = SpringBoard thermalmonitord

