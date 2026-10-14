# Thin wrapper around scripts/. All targets work when xcode-select points at the
# Command Line Tools: the scripts locate /Applications/Xcode*.app themselves.
SHELL := /bin/bash

.PHONY: help build debug run smoke dist check test strings strings-check probe probe-check icon list clean distclean

help:            ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'

build:           ## Release build, universal -> build/Cranny.app
	@scripts/build.sh

debug:           ## Debug build -> build/Cranny.app
	@CONFIGURATION=Debug ARCHS="$$(uname -m)" scripts/build.sh

run:             ## Debug build + launch (via LaunchServices)
	@scripts/run.sh

smoke:           ## Launch build/Cranny.app with --diagnostics and verify bundles/bridge/menu
	@scripts/smoke.sh

dist: build      ## zip + dmg (+ notarization when NOTARY_PROFILE is set) -> dist/
	@scripts/dist.sh

check:           ## Build every CrannyKit target separately (swift build --target)
	@scripts/check-modules.sh

test:            ## swift test for CrannyKit
	@. scripts/lib.sh && ensure_xcode && cd Packages/CrannyKit && swift test --scratch-path .build-test

strings:         ## Sync String Catalogs with keys used in code
	@scripts/sync-strings.sh

strings-check:   ## Fail if String Catalogs are out of date (CI)
	@CHECK=1 scripts/sync-strings.sh

probe:           ## Regenerate the SDK name-collision probe after adding public CrannyCore types
	@scripts/name-probe.sh

probe-check:     ## Fail if the SDK name-collision probe is out of date (CI)
	@CHECK=1 scripts/name-probe.sh

icon:            ## Re-render the App/AppIcon.icon layers (scripts/render-icon.swift)
	@. scripts/lib.sh && ensure_xcode && xcrun swift scripts/render-icon.swift App/AppIcon.icon/Assets

list:            ## xcodebuild -list
	@. scripts/lib.sh && ensure_xcode && xcodebuild -list -project Cranny.xcodeproj

clean:           ## Remove build outputs
	rm -rf build dist

distclean: clean ## Also remove SwiftPM scratch dirs
	rm -rf Packages/CrannyKit/.build Packages/CrannyKit/.build-* Packages/CrannyKit/.swiftpm
