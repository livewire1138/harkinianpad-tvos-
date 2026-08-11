# HarkinianTV: first tvOS port

This repository now contains an **experimental compile-first tvOS port** of
HarkinianPad. It reuses the Metal, SDL audio/lifecycle, controller, extraction,
and ROM-safety work from iOS while producing a distinct `HarkinianTV.app`.
It is a first engineering slice, not a playable release claim.

## What this first slice adds

- Apple TV device (`TVOS`) and Apple TV Simulator (`SIMULATOR_TVOS`) Xcode
  configurations, targeting arm64 and tvOS 14 or newer.
- A tvOS application bundle with device family 3, Metal and arm64
  requirements, and extended-gamepad support.
- The iOS portable dependency and lifecycle paths on tvOS, with scripting
  still hard-disabled. The build defines both `__IOS__` (the existing shared
  mobile implementation guard) and `__TVOS__` (for future platform-specific
  refinements).
- Controller-first navigation inherited from the mobile port. Touch controls
  are not a supported tvOS input method.

## Build

A Mac with Xcode, the dependencies from [BUILDING.md](BUILDING.md), and no ROM
is sufficient for a compile proof:

```sh
# Apple TV Simulator
scripts/build-tvos.sh --simulator

# Unsigned physical Apple TV compile proof
scripts/build-tvos.sh --device

# Signed device build
DEVELOPMENT_TEAM=ABCDE12345 \
BUNDLE_ID=com.yourname.harkiniantv \
scripts/build-tvos.sh --device
```

The products are expected at:

```text
build-tvos-soh-sim/soh/Release-appletvsimulator/HarkinianTV.app
build-tvos-soh/soh/Release-appletvos/HarkinianTV.app
```

The lower-level configuration command is `scripts/configure-tvos.sh` and
accepts the same `--device` or `--simulator` selection. Version overrides use
`HARKINIANPAD_VERSION` and `HARKINIANPAD_BUILD_NUMBER` for now so the two
platform builds can be cut from the same source version.

## Known gaps and next refinements

1. **Game-data onboarding is not solved.** tvOS has no iOS-style Files-visible
   Documents workflow. Do not put a ROM or ROM-derived `oot.o2r` in this
   repository or app bundle. A follow-up needs a legal, user-controlled local
   transfer flow (for example, a local-network importer with explicit consent
   and hash validation) before this becomes generally playable.
2. **The Simulator is only a compile/launch gate.** Rendering, audio,
   suspend/resume, save persistence, and memory pressure must be checked on a
   physical Apple TV.
3. **Controller behavior needs hardware evidence.** Verify menu navigation,
   gameplay mappings, disconnect/reconnect, rumble, and any Siri Remote
   fallback separately. An extended game controller should be considered a
   requirement for this preview.
4. **Branding is provisional.** The first slice deliberately omits the iOS
   asset catalog because tvOS requires layered app icons and a top-shelf image.
5. **Shared mobile guards should be renamed later.** `__IOS__` currently means
   the common UIKit/SDL mobile path. Once the build is green, migrate shared
   code to an Apple-mobile macro and isolate true iOS-only Files/touch UI.

## Acceptance sequence

Run the repository safety audit, configure and compile the Simulator, launch
without game data, and confirm that the missing-data screen remains usable
with a forwarded controller. Then repeat a signed build on Apple TV hardware
before implementing onboarding. No tvOS milestone should be called complete
until user-supplied game data, saves, lifecycle, audio, and controller tests
all pass without weakening the repository's ROM-free boundary.
