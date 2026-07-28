# HarkinianPad on tvOS: platform research and port plan

Research date: 2026-07-28. This is a design investigation, not evidence that a
tvOS build currently configures, installs, or runs. The existing iOS/iPadOS
port remains the implementation baseline.

## Executive summary

A native tvOS port looks technically feasible. The engine's important pieces
— arm64 ahead-of-time game code, SDL, Metal, controller input, audio, and
sandboxed writable data — all have tvOS equivalents. The largest product
difference is not rendering or CPU execution; it is **getting the user's ROM
into an app that has no normal Files-based import experience**. The touch
overlay also has no tvOS equivalent, so first launch, setup, menus, and gameplay
must all be operable with a remote or game controller.

The recommended first version is:

1. Build a separate `appletvos` product from the same pinned sources and keep
   tvOS-specific code behind a distinct `__TVOS__`/`TARGET_OS_TV` condition.
2. Persist configuration, saves, the uploaded ROM, and generated `oot.o2r` in
   the app container, never in the read-only bundle or purgeable caches.
3. Replace iOS Files discovery with a **foreground-only, authenticated local
   web uploader**. Display an address and one-time code on the television;
   upload from a phone or computer on the same LAN; validate and extract on the
   Apple TV; then delete the original ROM if the user opts in.
4. Treat a conventional extended gamepad as the supported gameplay device for
   the first usable build. Provide enough Siri/Apple TV Remote navigation to
   complete setup, open/close menus, and understand that a controller is
   required; do not attempt to translate the iOS touch overlay.

RetroArch is useful precedent for the local web-uploader interaction, but it
does not remove HarkinianPad's responsibility to implement sandbox placement,
upload authentication, lifecycle handling, ROM validation, legal boundaries,
and a controller-complete setup flow.

## What changes from the current iOS/iPadOS port

| Area | iOS/iPadOS today | tvOS consequence |
|---|---|---|
| User file access | `UIFileSharingEnabled`, a Files-visible `Documents` directory, and in-app rescan | Do not design around Files, a document picker, drag-and-drop, or an “On My Apple TV” workflow. Use an app-owned ingest channel. |
| Direct manipulation | UIKit touch overlay supplies every N64 input | There is no touch screen. Remove the overlay from the tvOS target and make every app screen focus/controller navigable. |
| Primary controller | Touch, keyboard/mouse, or SDL game controller | Game controller is the realistic gameplay baseline. Remote input is best used for setup/menu navigation unless a deliberate, usable N64 mapping is proven. |
| UI model | Touch targets layered over an SDL/Metal view | tvOS UIKit is focus-driven. Native setup controls need visible focus; ImGui needs reliable D-pad/accept/back navigation and must not compete with UIKit focus. |
| Display | Many phone/tablet sizes, orientations, and cutouts | Full-screen television output is normally landscape, but safe-area/overscan and 1080p/4K point-versus-pixel scaling still require testing. |
| Storage | App container plus Files visibility | The sandbox is still writable, but only the app normally presents its contents. Durable data must not be placed in `Caches` or `tmp`. |
| Lifecycle | Frequent touch use; existing SDL pause/resume bridge | The system may suspend or terminate while the TV switches apps or sleeps. Stop Metal/audio/network work, close partial uploads safely, and flush saves/configuration on resignation/background events. |
| Distribution | `.ipa` for `iphoneos` | A separate tvOS bundle, provisioning profile, deployment target, icons/top-shelf metadata as applicable, and Apple TV install path are required. An iOS IPA is not a universal Apple TV package. |

Apple's tvOS overview describes the platform as sharing technologies such as
Metal and UIKit while using the focus model for television interaction.
Apple's file-system guidance also distinguishes durable Application Support or
Documents data from recreatable Caches data. See the primary references at the
end of this document.

## ROM and archive acquisition

### Why the iOS flow does not carry over

The current port makes `Documents` Files-visible and scans it for a supported
ROM. A tvOS sandbox can still create and read files, but “the directory exists”
does not imply “the customer has a system file browser that can put a ROM
there.” In particular, a tvOS plan should not depend on:

- `UIDocumentPickerViewController` or security-scoped URLs;
- `UIFileSharingEnabled`/Finder file sharing;
- an “On My Apple TV” Files location;
- AirDrop into the app; or
- leaving a ROM in the signed application bundle.

Those are separate access mechanisms, not generic consequences of using
`Documents`. Keep the extraction pipeline, but replace the acquisition edge.

### Recommended: local-network web upload

This is the closest match to the RetroArch-style experience suggested in the
request and requires no companion app or cloud account.

Proposed flow:

1. On first launch, create an upload session and show a large URL, such as
   `http://harkinianpad.local:8080`, its numeric-IP fallback, and a short random
   code. A QR code is a convenience, not the only route.
2. Start the listener only while the setup screen is visible and the app is
   foreground-active. Use Network.framework (`NWListener`) or a small,
   maintained HTTP implementation; do not add a general-purpose desktop web
   stack merely for this screen.
3. The browser uploads exactly one allowed ROM candidate. Stream it to a
   randomly named file under `tmp` or an `Imports/InProgress` directory while
   enforcing a conservative size cap. Never buffer the entire HTTP body in
   memory.
4. Verify extension only as a hint; use the existing ROM content/hash/version
   checks as authority. On failure, remove the partial file and show a useful
   error on both browser and TV.
5. Atomically move a validated input to durable app storage, stop the listener,
   run the existing on-device `oot.o2r` extraction UI, fsync/close the archive,
   then atomically publish it under its final name.
6. Offer to delete the source ROM after successful archive creation. Never
   expose a download endpoint for the ROM or generated game-data archive.

Security and privacy requirements:

- declare `NSLocalNetworkUsageDescription`; declare Bonjour service types if
  Bonjour discovery is actually advertised;
- require a high-entropy per-session secret in the URL in addition to any
  human-entered short code, expire it, and rate-limit guesses;
- bind only for the active setup session, reject additional/parallel uploads,
  disable directory listing, and return restrictive cache headers;
- show the device name/address and an immediate **Stop upload server** action;
- assume the LAN is hostile: sanitize filenames, ignore client paths/MIME
  claims, cap headers/body/time, and never allow arbitrary destination paths;
- remove incomplete files after interruption, backgrounding, timeout, or cold
  launch; and
- do not promise HTTPS security from an ad-hoc self-signed certificate. A
  short-lived authenticated HTTP session on the user's LAN has an explicit
  threat tradeoff; a paired companion/cloud design is needed if stronger
  transport identity is a requirement.

Apple's local-network privacy guidance covers the permission prompt and
Bonjour declaration. Network.framework supplies the supported listener API.
RetroArch's Apple-platform documentation and tvOS source tree are prior art for
the user experience, not an API contract for this project.

### Alternatives and tradeoffs

| Option | Advantages | Problems / appropriate use |
|---|---|---|
| Paired iPhone/iPad app | Strong native UX; can use the phone's Files picker and authenticated device-to-device transfer | A second product, signing target, protocol, review surface, and support burden. Good later, not the shortest port. |
| iCloud/CloudKit import | No inbound LAN listener; sync can be authenticated by Apple ID | Requires entitlements/account/network, upload UI elsewhere, quota/error handling, and a clear policy for copyrighted user data. CloudKit is not a generic shared filesystem. |
| User-supplied remote URL | Small TV UI | Encourages typing, creates SSRF/download/legal hazards, and can become an accidental ROM-distribution workflow. Do not implement. |
| Xcode/device-container injection | Useful for developer bring-up and repeatable tests | Not an end-user feature and unavailable to ordinary sideload users. |
| Bundle `oot.o2r` or ROM | Easiest runtime | Violates this repository's ROM-free boundary; bundle is read-only and increases package/review risk. Not acceptable. |
| Generate archive on Mac/PC, then upload it | Avoids extraction time/memory on Apple TV | Requires a separately distributed exporter and must still validate archive/version. Could be an advanced option, but ROM upload plus on-device extraction preserves today's product model. |

### Storage layout

Use one path service rather than scattering `HOME` assumptions through the
engine. A reasonable tvOS layout is:

```text
Library/Application Support/HarkinianPad/
  game/oot.o2r              durable, user-derived runtime archive
  imports/source.z64        optional durable ROM until extraction succeeds
  config/                   settings and controller mappings
Documents/                  saves, if retained for semantic continuity
Library/Caches/             regenerable caches only
tmp/uploads/                partial upload only; cleaned aggressively
```

Resolve directories with `NSFileManager`/Foundation (or SDL's platform path
API after verifying its tvOS result), create them with data-protection options
available on the target, and exclude large regenerable artifacts from backup
where Apple policy calls for it. Do **not** place the only copy of saves or
`oot.o2r` in `Caches` or rely on `tmp` surviving.

Storage pressure needs first-class UX. Before accepting an upload, check free
capacity for the ROM, extractor working set, and completed archive at the same
time. Report required/available space rather than allowing a late `zip_close`
failure. The prior iOS investigation estimated extraction at roughly 350–550
MB peak RSS; that estimate must be measured on the oldest supported Apple TV,
and extraction should occur before the full game heap is initialized.

## Input, focus, and remote mechanics

### Gameplay

Shipwright's controller path already runs through SDL's game-controller API,
which is the right abstraction to test on tvOS. Do not assume that successful
iOS pairing proves tvOS behavior: reconnect, player index, Guide/Menu capture,
rumble, motion, and controller-family mappings need an Apple TV matrix.

Recommended policy for an initial build:

- require an extended gamepad for gameplay and say so before ROM upload;
- keep D-pad/left-stick menu navigation, accept, cancel/back, Start, and the
  Shipwright menu reachable without a keyboard;
- hot-plug and reconnect without losing menu access;
- show controller state and a simple button test on the setup screen; and
- preserve a safe route out of gameplay even where the system reserves a
  controller's Home/Guide button.

The Apple TV Remote appears through GameController APIs as a micro gamepad on
supported system versions, but its directional surface and small button set
are not a comfortable substitute for an N64 controller. A remote-only mapping
would require explicit product design (modes/chords and discoverability), not
just accepting whatever SDL emits. At minimum the remote should navigate the
native setup/error UI. Whether App Store distribution imposes additional
remote-support requirements must be rechecked against the review rules in
force at submission time.

### Focus ownership

UIKit focus and ImGui controller navigation can both respond to the same
directional input. Establish a single owner:

- native first-run/upload screens: UIKit focus owns navigation and the SDL
  gameplay view is inactive;
- gameplay: SDL/Shipwright owns controller events;
- Shipwright menus: ImGui gamepad navigation owns events, with explicit
  accept/back mappings; and
- transitions: release held inputs and debounce the event that changed modes
  so it cannot also activate the newly focused control.

Use the tvOS focus environment and focus guides for native controls. Never make
a cursor, touch, hardware keyboard, or text field the only way to proceed.
Avoid asking the user to type an IP address on the TV: the TV displays it and
the phone/computer browser types it.

## Rendering, audio, lifecycle, and performance

### Metal and display

The existing SDL-created `CAMetalLayer` and Metal renderer should be reused,
but “same framework” is not “no work”:

- compile every Objective-C++ platform guard against the tvOS SDK; UIKit APIs
  available on iOS may be unavailable or behave differently on tvOS;
- use drawable size rather than assuming 1920×1080, and test 1080p and 4K;
- keep UI inside safe-area/overscan margins and make text readable at couch
  distance;
- test television refresh-rate/frame-pacing behavior and avoid presenting
  while inactive/backgrounded; and
- remove touch overlay construction from the target rather than merely hiding
  transparent views over the Metal surface.

### Audio

SDL audio is still the preferred portable path. tvOS does not receive phone
calls, but Siri, system UI, HDMI route changes, AirPods/Bluetooth devices,
sleep/wake, and app switching can interrupt or change audio. Re-run the audio
format negotiation and pause/clear/resume tests; do not reuse an iPad result as
proof. Background audio is neither needed nor desirable for this game.

### Lifecycle and persistence

Reuse the existing SDL lifecycle bridge concept, then verify tvOS event
delivery. On resign/background:

1. stop accepting network connections and close/remove partial uploads;
2. stop frame submission and GPU access;
3. pause/clear audio as appropriate;
4. atomically flush configuration and save data; and
5. release disposable extraction buffers.

On foreground, recreate/resize drawable state if needed, re-enumerate
controllers, and resume only after the app is active. Do not rely on a
termination callback: suspended apps may be killed without one.

## Build-system and source changes

The current patch set uses `__IOS__` as a broad mobile-Apple switch and emits
an iPhoneOS application. A maintainable tvOS fork should avoid pretending
tvOS is iOS while still sharing common code.

1. Add a tvOS configure/package mode, for example `scripts/build-tvos.sh`
   (or a platform option in the existing script), with `appletvos` and
   `appletvsimulator` destinations. Confirm the exact `ios-cmake` platform
   spelling and CMake `CMAKE_SYSTEM_NAME` against the pinned toolchain rather
   than guessing in CI.
2. Build SDL 2.32.10 for tvOS from the pinned dependency and audit its enabled
   UIKit, Metal, audio, GameController, and main-entrypoint sources. A library
   advertising tvOS support does not prove this particular static CMake graph
   links.
3. Define platform predicates in one header:

   ```c
   #include <TargetConditionals.h>
   #if TARGET_OS_TV
   #define __TVOS__ 1
   #elif TARGET_OS_IOS
   #define __IOS__ 1
   #endif
   #define __APPLE_MOBILE__ 1 /* only where behavior is genuinely shared */
   ```

   In real code, define the shared macro only inside the applicable Apple
   mobile branch; the sketch illustrates intent, not a header ready to commit.
4. Split the Info.plist: tvOS bundle identifiers/versioning, orientations,
   controller declarations, local-network usage description, and any Bonjour
   services must be deliberate. Remove iOS file-sharing/document-opening keys
   and touch-only assumptions.
5. Exclude iOS touch-controller Objective-C++ from tvOS. Add a focused native
   setup/uploader view that can coexist with SDL's window/view lifecycle.
6. Generalize `Context` paths from `HOME/Documents` to a platform path service
   and migrate existing saves/config without changing desktop paths.
7. Audit all `__IOS__` occurrences in maintained patches. Classify each as
   Apple-mobile shared, iOS-only, or tvOS-only; pay particular attention to
   `UIApplication` window lookup, display bounds, text input, mouse/touch-event
   filtering, lifecycle events, and bundle-resource paths.
8. Keep scripting/JIT/native module loading disabled, as on iOS.

## Delivery sequence and proof gates

| Gate | Deliverable | Pass evidence |
|---|---|---|
| T0: toolchain | Minimal SDL/Metal tvOS target | Simulator and device compile/link logs; no ROM involved |
| T1: frame | Shipwright boots with developer-injected legal test archive | Physical Apple TV renders stable frames at measured resolution/rate |
| T2: input | Controller-first title/menu/gameplay | Remote completes setup UI; gamepad completes a sustained gameplay test; reconnect passes |
| T3: storage | Durable paths and migration | Save/config/archive survive suspend, cold launch, update, and storage-pressure scenario |
| T4: uploader | Foreground local web ingest | Permission UX, IP and `.local` paths, wrong-code/oversize/interrupted uploads, hostile filenames, and cleanup all pass |
| T5: extraction | ROM validation through local archive | Supported ROM extracts on the oldest target without jetsam; invalid variants fail cleanly; source deletion option works |
| T6: lifecycle | TV switching/sleep/audio/network matrix | No background GPU/network activity; saves persist; audio/controller recover |
| T7: package | ROM-free signed tvOS artifact | Package audit, Apple TV install/update, entitlements/privacy strings, and clean-machine replay pass |

Recommended hardware matrix: the oldest Apple TV generation chosen by the
deployment target, a current Apple TV 4K, Apple TV Remote, one Xbox-family
controller, one PlayStation-family controller, Ethernet and Wi-Fi, and at
least one network with Bonjour/client isolation disabled and one where `.local`
discovery fails (to prove numeric-IP fallback).

## Key risks and decisions still open

1. **Minimum Apple TV / tvOS version.** Choose it from SDL/toolchain support,
   memory measurements, and hardware access—not from the iOS 14 deployment
   target by analogy.
2. **Distribution scope.** Local developer/sideload build, TestFlight, and App
   Store each change signing, review, privacy, and support obligations.
3. **Gameplay without an extended controller.** Recommended answer for v1 is
   “not supported,” while retaining remote-complete setup. This needs explicit
   product acceptance.
4. **Keep or delete uploaded ROM.** Defaulting to delete-after-success reduces
   storage and exposure; retaining it makes archive regeneration easier.
5. **Archive upload as an advanced mode.** It saves TV extraction resources but
   adds exporter distribution/version UX. Defer until ROM upload is measured.
6. **Local HTTP threat model.** A random, short-lived session is reasonable for
   a local-only developer product; a higher-assurance consumer flow may justify
   a paired companion app.
7. **App Store policy.** Emulator/source-port, user-supplied game data, remote
   support, privacy disclosures, and dynamically supplied content requirements
   are time-sensitive and need a fresh, written review immediately before any
   submission. Technical feasibility is not approval evidence.

## Primary references

- Apple, [Designing for tvOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos)
  and [Supporting focus within your app](https://developer.apple.com/documentation/uikit/supporting-focus-within-your-app).
- Apple, [Local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
  and [Building a custom peer-to-peer protocol](https://developer.apple.com/documentation/network/building-a-custom-peer-to-peer-protocol).
- Apple, [Reducing your app's impact on the file system](https://developer.apple.com/documentation/xcode/reducing-your-app-s-impact-on-the-file-system)
  and the [File System Programming Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/).
- Apple, [Game Controller framework](https://developer.apple.com/documentation/gamecontroller)
  and [Handling controller inputs](https://developer.apple.com/documentation/gamecontroller/handling-controller-inputs).
- Apple, [Metal best practices for tvOS](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/AppleTV.html).
- SDL, [README-ios](https://github.com/libsdl-org/SDL/blob/SDL2/docs/README-ios.md)
  and [SDL's Apple TV platform source](https://github.com/libsdl-org/SDL/tree/SDL2/src/video/uikit).
- RetroArch, [Apple platform documentation](https://docs.libretro.com/guides/install-ios/)
  and [Apple-platform frontend source](https://github.com/libretro/RetroArch/tree/master/pkg/apple).

These references establish platform APIs and useful precedent. The only valid
proof for HarkinianPad remains a build and runtime test against its pinned
SDL, toolchain, Shipwright, and libultraship revisions.
