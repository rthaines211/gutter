## Personal settings (device IDs, backend URL, push key) live in the untracked
## Makefile.local. Without it these stay empty: the build has no default server
## and no baked-in push key, and the device targets need IPAD_DEVICE_ID /
## IPHONE_DEVICE_ID passed on the command line.
-include Makefile.local
IPAD_DEVICE_ID ?=
IPHONE_DEVICE_ID ?=
BUNDLE_ID ?= com.ryanhaines.comicReaderApp
BACKEND_DIR ?=
BACKEND_URL ?=
COMPOSE_DIR ?=
PUSH_API_KEY ?=
APP = build/ios/iphoneos/Runner.app

DART_DEFINES = --dart-define=FLAVOR=personal \
	$(if $(PUSH_API_KEY),--dart-define=PUSH_API_KEY=$(PUSH_API_KEY)) \
	$(if $(BACKEND_URL),--dart-define=DEFAULT_SERVER_URL=$(BACKEND_URL))

.PHONY: ipad ipad-release ipad-debug iphone iphone-release iphone-debug store-ipad store-ipa clean devices backend-check backend-deploy unlock check

## Install over the existing app instead of `flutter install`, which uninstalls
## first and wipes the app's data (server URL, mirror DB, downloads) every time.
install_to = xcrun devicectl device install app --device $(1) $(APP)

## Two apps from one codebase, installed side by side. The Runner target reads
## its bundle id, home-screen name and entitlements from Flavor.xcconfig
## (untracked), written before every build. The pbxproj has no fallback, so a
## build without it fails at signing instead of shipping the wrong bundle id.
## Personal keeps BUNDLE_ID so `make ipad` upgrades in place and keeps its data.
STORE_BUNDLE_ID = com.ryanhaines.gutter
write_flavor = printf 'GUTTER_BUNDLE_ID = %s\nGUTTER_DISPLAY_NAME = %s\nGUTTER_ENTITLEMENTS = %s\n' $(1) $(2) $(3) > ios/Flutter/Flavor.xcconfig
personal_flavor = $(call write_flavor,$(BUNDLE_ID),Longbox,Runner/Runner.entitlements)
store_flavor = $(call write_flavor,$(STORE_BUNDLE_ID),Gutter,Runner/Store.entitlements)

## First codesigning identity in the keychain, read at build time rather than
## hardcoded: keeps the cert's email and team ID out of the repo, and survives
## the certificate being reissued under a new name.
CODESIGN_IDENTITY = $(shell security find-identity -v -p codesigning | \
	awk -F'"' 'NR==1 {print $$2}')
KEYCHAIN ?= $(HOME)/Library/Keychains/login.keychain-db

## Unlock the login keychain and grant codesign access to the signing key.
## Prompts once for the login password; it is read into a variable rather than
## passed on the command line, so it stays out of shell history and `ps`.
##
## Over SSH there is no GUI session to authorize keychain access, so codesign
## fails with errSecInternalComponent unless the key's partition list names it
## explicitly. -D targets one certificate: without it the ACL update lands on
## whichever keys happen to match and the build still fails.
##
## With BUILD_KEYCHAIN_PASS in Makefile.local (scripts/setup-build-keychain.sh),
## KEYCHAIN is a signing-only keychain and is unlocked with no prompt.
unlock:
	@if security show-keychain-info $(KEYCHAIN) >/dev/null 2>&1; then \
		echo "Keychain already unlocked."; exit 0; fi; \
	if [ -n "$(BUILD_KEYCHAIN_PASS)" ]; then \
		security unlock-keychain -p "$(BUILD_KEYCHAIN_PASS)" $(KEYCHAIN) && echo "Build keychain unlocked."; exit $$?; fi; \
	test -n "$(CODESIGN_IDENTITY)" || \
		{ echo "No codesigning identity found. Check: security find-identity -v -p codesigning"; exit 1; }; \
	read -r -s -p "Login password for the keychain: " pw; echo; \
	security unlock-keychain -p "$$pw" $(KEYCHAIN) && \
	security set-key-partition-list -S apple-tool:,apple:,codesign: \
		-s -k "$$pw" -D "$(CODESIGN_IDENTITY)" -t private $(KEYCHAIN) > /dev/null && \
	echo "Keychain unlocked; codesign granted access to $(CODESIGN_IDENTITY)."

## Gate every device build: analyzer (infos allowed) + full test suite (~3 min).
## Skip in a pinch with `make -o check ipad`.
check:
	flutter analyze --no-fatal-infos
	flutter test

## Install release build to iPad over WiFi
ipad: ipad-release

ipad-release: check unlock backend-check
	$(personal_flavor)
	flutter build ios --release $(DART_DEFINES)
	$(call install_to,$(IPAD_DEVICE_ID))

## Verify the backend is reachable (warns, never blocks the build)
backend-check:
	@if [ -z "$(BACKEND_URL)" ]; then echo "No BACKEND_URL (Makefile.local); skipping backend check."; \
	elif curl -s --max-time 2 $(BACKEND_URL)/reading > /dev/null 2>&1; then \
		echo "Backend up at $(BACKEND_URL)."; \
	else \
		echo "WARNING: backend not reachable at $(BACKEND_URL) — is the comic-reader container running? (make backend-deploy)"; \
	fi

## Rebuild and restart the comic-reader container from the backend repo's main.
## This Mac is the Docker host, so no SSH: fast-forward the build context, then
## rebuild only this service (the rest of the media stack is untouched).
backend-deploy:
	@test -n "$(BACKEND_DIR)" -a -n "$(COMPOSE_DIR)" || { echo "Set BACKEND_DIR and COMPOSE_DIR in Makefile.local"; exit 1; }
	git -C $(BACKEND_DIR) pull --ff-only
	cd $(COMPOSE_DIR) && docker compose build comic-reader && docker compose up -d comic-reader

## Install debug build to iPad over WiFi
ipad-debug: unlock backend-check
	$(personal_flavor)
	flutter build ios --debug $(DART_DEFINES)
	$(call install_to,$(IPAD_DEVICE_ID))

## Install release build to iPhone
iphone: iphone-release

iphone-release: check unlock backend-check
	$(personal_flavor)
	flutter build ios --release $(DART_DEFINES)
	$(call install_to,$(IPHONE_DEVICE_ID))

## Install debug build to iPhone
iphone-debug: unlock backend-check
	$(personal_flavor)
	flutter build ios --debug $(DART_DEFINES)
	$(call install_to,$(IPHONE_DEVICE_ID))

## The App Store app on the iPad, next to the personal one: no FLAVOR (store is
## the default), no default server, no push key.
store-ipad: check unlock
	$(store_flavor)
	flutter build ios --release
	$(call install_to,$(IPAD_DEVICE_ID))

## Archive the store app for App Store Connect (build/ios/ipa).
store-ipa: check unlock
	$(store_flavor)
	flutter build ipa --release

## List connected devices
devices:
	flutter devices

## Clean build artifacts
clean:
	flutter clean
