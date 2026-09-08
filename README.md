# BegoTorch

Torch brightness control app for begonia (Xiaomi Mi 9T / Redmi K20).

## What it does

A round 8-stop slider (brightness 0–7) that writes the torch level as root:

    su -c 'echo "N" > /sys/devices/platform/flashlights_mt6360/torchbrightness'

The app probes the usual `su` locations and uses the first one that runs:

    /system/bin/su, /system/xbin/su, /su/bin/su, /data/adb/ap/bin/su,
    /sbin/su, /magisk/.core/bin/su

On APatch-family roots (APatch, FolkPatch) the kernel's sucompat layer
intercepts execve of `/system/bin/su`, so the first candidate normally
answers even though the real binary lives under `/data/adb/ap/bin`.

## Quick Settings tile

`TorchTileService` (Kotlin, `android/app/src/main/kotlin/`) adds a
"Torch" tile that toggles brightness 0 ↔ 7 with a single tap:

- Resolves `su` with the same probe order as the Dart side.
- Writes on a worker thread; never blocks the main thread on root calls.
- State syncs from the sysfs node when the panel opens, with a
  SharedPreferences fallback (the app can't usually read the node directly).

Add it from the QS editor (drag the "Torch" tile into the panel). Requires
the same root grant as the app.

## Requirements

- A rooted Android device (Magisk / KernelSU / APatch / FolkPatch) with the
  `su` binary reachable from the app and the root grant approved for BegoTorch.
- The mt6360 flashlight sysfs node as exposed by the begonia kernel.

## Build

GitHub Actions builds a release APK on every push to `main`
(`.github/workflows/build.yml`) and uploads it as the
`begotorch-release-apk` artifact.

Locally:

    flutter pub get
    flutter analyze
    flutter test
    flutter build apk --release

