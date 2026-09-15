TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NovaTap

NovaTap_FILES = src/NovaTapEngine.m src/NovaTapHUD.m src/NovaTapEntry.m
NovaTap_CFLAGS = -fobjc-arc -Isrc -O3
NovaTap_FRAMEWORKS = UIKit Foundation CoreGraphics AVFoundation AudioToolbox

include $(THEOS_MAKE_PATH)/tweak.mk
