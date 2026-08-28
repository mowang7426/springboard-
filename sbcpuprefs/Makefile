
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SBCPUPrefs

SBCPUPrefs_FILES = SBCPUPrefsRootListController.m
SBCPUPrefs_FRAMEWORKS = UIKit
SBCPUPrefs_PRIVATE_FRAMEWORKS = Preferences
SBCPUPrefs_CFLAGS = -fobjc-arc

# 去掉了硬编码的安装路径，让 RootHide/Rootless Theos 自动决定存放位置
include $(THEOS_MAKE_PATH)/bundle.mk

