
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SBCPUPrefs

SBCPUPrefs_FILES = SBCPUPrefsRootListController.m
SBCPUPrefs_FRAMEWORKS = UIKit
SBCPUPrefs_PRIVATE_FRAMEWORKS = Preferences
SBCPUPrefs_CFLAGS = -fobjc-arc

# 🔴 核心修复：必须加回这一行！
# Theos 在 Rootless 环境会自动把它转成 /var/jb/... 
# 不加这行就会安装错位置，导致设置里找不到。
SBCPUPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
