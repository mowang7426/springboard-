
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SBCPUPrefs

SBCPUPrefs_FILES = SBCPUPrefsRootListController.m
SBCPUPrefs_FRAMEWORKS = UIKit
SBCPUPrefs_PRIVATE_FRAMEWORKS = Preferences
SBCPUPrefs_CFLAGS = -fobjc-arc

# 🔴 安装路径
SBCPUPrefs_INSTALL_PATH = /Library/PreferenceBundles
# 🔴 强制声明主类，防止系统因为找不到代码而隐藏插件
SBCPUPrefs_PRINCIPAL_CLASS = SBCPUPrefsRootListController

include $(THEOS_MAKE_PATH)/bundle.mk

