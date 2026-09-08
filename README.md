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

