ARCHS = arm64
TARGET = iphone:clang:26.5:15.0
INSTALL_TARGET_PROCESSES = Filzer

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Filzer

# App sources + PartyUI (github.com/jailbreakdotparty/PartyUI) vendored as a git
# submodule under Vendor/PartyUI. Theos has no SwiftPM dependency resolution in
# its actual compile step, so PartyUI's sources are compiled directly into the
# Filzer module alongside the app's own files (no `import PartyUI` needed/used;
# its public types are simply visible module-wide).
Filzer_FILES = $(shell find Sources -name '*.swift') \
	$(shell find Vendor/PartyUI/Sources/PartyUI -name '*.swift')
Filzer_FRAMEWORKS = UIKit SwiftUI

include $(THEOS_MAKE_PATH)/application.mk
