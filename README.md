# Evolution X for Redmi 9A (dandelion)

Build script, manifest and patches for **Evolution X 12.2 (Android 17)** on the Xiaomi
Redmi 9A (`dandelion`, MediaTek Helio G25 / MT6762). This is a full device build, not a GSI.
It is the Vanilla variant, without Google apps.

This is an experimental port. Android 17 officially needs a 5.4+ kernel and a vendor from
Android 12 or newer, but this build keeps the phone's **stock Android 10 vendor**
(MIUI V12.0.9.0) and its **prebuilt 4.9 kernel**. Patches across the platform make
that work (see below).

Evolution X comes from [Evolution-X](https://github.com/Evolution-X) (branch `cnb`,
LineageOS 24.0 / `android-17.0.0_r1`). The device and vendor trees come from
[alg810](https://github.com/alg810) (branch `13`, forward-ported here), and VNDK v29 from
AOSP `android-15.0.0_r31`.

## Status

| | |
| --- | --- |
| Boots to setup wizard (`sys.boot_completed=1`) | ✅ verified on a real Redmi 9A |
| Display, GPU (PowerVR), touch | ✅ UI renders and setup is usable |
| Audio service (HAL 5.0 via restored `libaudiohal@5.0`) | ✅ starts; playback not tested yet |
| Wi-Fi | ✅ enabled; connecting not tested yet |
| Cellular / SIM | ❔ not tested (SIM reported absent in the first test) |
| Camera, Bluetooth, fingerprint, sensors | ❔ not tested |
| Per-app data usage stats, tethering offload | ❌ need eBPF programs this kernel can't run |
| MTK picture-quality HAL (`PQServiceHAL`) | ⚠️ crash-loops (display still works) |

No prebuilt zip yet. It will come once a non-debug build has been tested.

## What had to change (and why)

Every patch has a header explaining it. In short:

| Project | Fix |
| --- | --- |
| `bionic` | `arc4random` aborted on 4.9 (no `MADV_WIPEONFORK`), killing every process starting with `init`. It now falls back to pid-based fork detection. |
| `system/sepolicy` | Restores the 29.0/30.0 vendor-policy mappings (Android 17 only ships 31.0+). |
| `packages/modules/vndk` | Adds the `com.android.vndk.v29` APEX. |
| `system/linkerconfig` | Empty defaults for VNDK/sanitizer variables. The bootstrap run aborted before the VNDK APEX was mounted. |
| `packages/modules/Connectivity` | Opt-in legacy-kernel support: the BPF loader uses its ELF path, skips rejected objects and maps LRU/LPM to HASH. `netd` skips the 5.4+ gates. Ring-buffer (5.8+) users are skipped. |
| `system/core` | `ueventd` imports the legacy `/vendor/ueventd.rc`, which gives `/dev/ion` and the PowerVR nodes their permissions. |
| `frameworks/base` | `HintManagerService` no longer crashes without an AIDL PowerHAL. |
| `frameworks/av` | Restores the `libaudiohal@5.0` client. Otherwise `audioserver` crashes and `system_server` hangs in `AudioService`. |
| `build/make` | releasetools tolerates the missing vendor partition. |
| `build/soong` | 20 GB soft heap limit for `soong_build` (30 GB RAM hosts). |
| `vendor/gms` | Skips the 64-bit-only TurboAdapter on this 32-bit build. |
| `device/xiaomi/dandelion` | The forward port itself: Evolution X flags, A-only, dynamic partition sizing, `legacy_gralloc` (gralloc 2.x vendor), USB controller and state, SELinux fixes, A17 API updates. |

`debug/` holds the logging aids used during bring-up: a boot logger, permissive SELinux,
`printk.devkmsg` and an `init` panic hook. `build.sh` does **not** apply them.

## Requirements

- Linux x86_64 (tested on Ubuntu 26.04, 16 threads, 30 GB RAM + 32 GB swap)
- ~300 GB free disk
- Tools: `repo git git-lfs python3 ccache zip unzip bc bison flex rsync xxd lz4 zstd make gcc openssl m4`

## Build

```bash
git clone https://github.com/qcom-toolbox/EVOLUTION-X-DANDELION-17
cd EVOLUTION-X-DANDELION-17
./build.sh            # sync + apply patches + build (userdebug)
```

Options match [EVOLUTION-X-LANCELOT-17](https://github.com/qcom-toolbox/EVOLUTION-X-LANCELOT-17):
`-d DIR`, `-j N`, `-v user|userdebug|eng`, `-s` (sync only), `-b` (build only),
`-c` (installclean). `manifests/tested-revisions.xml` pins the exact source revisions
this was verified with. Evolution X's `cnb` branch moves, so use it if the patches stop
applying.

## Flashing

> ⚠️ Experimental. Back up **everything** first, including your NV partitions (`nvram`,
> `nvdata`, `nvcfg`, `persist`, `proinfo`, `protect1/2`). Keep the backups private: they
> contain your IMEI. MediaTek BROM + [mtkclient](https://github.com/bkerler/mtkclient)
> is the way back if the phone stops reaching fastboot.

This needs an unlocked bootloader and a **dandelion** TWRP. TWRP builds for other
models (e.g. `blossom`) hang on this phone.

1. In TWRP: flash the zip (sideload or `twrp install`).
2. **Wipe → Format Data** (required coming from another ROM; wipes everything).
3. Reboot. The first boot takes a few minutes.

Notes:
- On first boot the ROM **replaces the recovery partition** with its own recovery.
  Re-flash TWRP from fastboot if you need it: `fastboot flash recovery twrp.img`.
- The USB fix in the release patch (`init.dandelion.usb.rc`) seeds the USB state from the
  build default. The bring-up build hard-coded `adb` there, so report it if USB/adb
  doesn't come up.

## Credits

Evolution X, LineageOS, AOSP, alg810 (dandelion trees), and everyone keeping the
MT6762/MT6765 devices alive.

## License

The build script, manifests, patches and docs in this repo are licensed under the
[Apache License 2.0](LICENSE). Evolution X, LineageOS, AOSP and the device trees keep their
own licenses. The proprietary vendor blobs belong to Xiaomi/MediaTek and are not covered.
