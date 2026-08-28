
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SBCPUPrefs

SBCPUPrefs_FILES = SBCPUPrefsRootListController.m
SBCPUPrefs_FRAMEWORKS = UIKit
SBCPUPrefs_PRIVATE_FRAMEWORKS = Preferences
SBCPUPrefs_INSTALL_PATH = /Library/PreferenceBundles
SBCPUPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

