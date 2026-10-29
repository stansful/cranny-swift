# Thin wrapper around scripts/. All targets work when xcode-select points at the
# Command Line Tools: the scripts locate /Applications/Xcode*.app themselves.
SHELL := /bin/bash

.PHONY: help release build-release scripts-test build debug run smoke dist check test strings strings-check copy-check l10n-check l10n-pending probe probe-check icon list clean distclean

help:            ## Show this help
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'

release:         ## New version in VERSION + commit "feat: release - version X.Y.Z" (scripts/make-release.sh; ARGS=patch|X.Y.Z)
	@scripts/make-release.sh $(ARGS)

build-release:   ## Release files of VERSION as GitHub builds them -> dist/ (scripts/build-release.sh; ARGS=--test)
	@scripts/build-release.sh $(ARGS)

scripts-test:    ## Tests of the release scripts and workflows (scripts/tests/run.sh; no build)
	@scripts/tests/run.sh

build:           ## Release build, universal -> build/Cranny.app
	@scripts/lib/build.sh

debug:           ## Debug build -> build/Cranny.app
	@CONFIGURATION=Debug ARCHS="$$(uname -m)" scripts/lib/build.sh

run:             ## Debug build + launch (via LaunchServices)
	@scripts/lib/run.sh

smoke:           ## Launch build/Cranny.app with --diagnostics and verify bundles/bridge/menu
	@scripts/lib/smoke.sh

dist: build      ## zip + dmg (+ notarization when NOTARY_PROFILE is set) -> dist/
	@scripts/lib/dist.sh

check:           ## Build every CrannyKit target separately (swift build --target)
	@scripts/lib/check-modules.sh

test:            ## swift test for CrannyKit
	@. scripts/lib/common.sh && ensure_xcode && ensure_metal_toolchain && cd Packages/CrannyKit && swift test "$${SWIFTPM_BUILD_SYSTEM[@]}" --scratch-path .build-test

strings:         ## Sync String Catalogs with keys used in code
	@scripts/lib/sync-strings.sh

strings-check:   ## Fail if String Catalogs are out of date, break the copy rules or miss a shipped language (CI)
	@CHECK=1 scripts/lib/sync-strings.sh
	@/usr/bin/python3 -I scripts/lib/lint-copy.py
	@/usr/bin/python3 -I scripts/lib/l10n/validate.py --shipped

copy-check:      ## Copy rules of every String Catalog, per language (no build; part of strings-check)
	@/usr/bin/python3 -I scripts/lib/lint-copy.py

l10n-check:      ## Shipped languages complete + valid: scripts/lib/l10n/validate.py --shipped (no build; part of strings-check)
	@/usr/bin/python3 -I scripts/lib/l10n/validate.py --shipped

l10n-pending:    ## Mark new English strings pending translation in every shipped language (docs/TRANSLATING.md)
	@/usr/bin/python3 -I scripts/lib/l10n/pending.py

probe:           ## Regenerate the SDK name-collision probe after adding public CrannyCore types
	@scripts/lib/name-probe.sh

probe-check:     ## Fail if the SDK name-collision probe is out of date (CI)
	@CHECK=1 scripts/lib/name-probe.sh

icon:            ## Re-render the App/AppIcon.icon layers (scripts/lib/render-icon.swift)
	@. scripts/lib/common.sh && ensure_xcode && xcrun swift scripts/lib/render-icon.swift App/AppIcon.icon/Assets

list:            ## xcodebuild -list
	@. scripts/lib/common.sh && ensure_xcode && xcodebuild -list -project Cranny.xcodeproj

clean:           ## Remove build outputs
	rm -rf build dist

distclean: clean ## Also remove SwiftPM scratch dirs
	rm -rf Packages/CrannyKit/.build Packages/CrannyKit/.build-* Packages/CrannyKit/.swiftpm
