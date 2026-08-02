# LineageOS 22.2 (Android 15) for Moto G5S Plus (sanders)

> ## ⛔ TWRP CANNOT INSTALL THIS ROM — you must use LineageOS Recovery
>
> **If TWRP gave you `Error 1` / "Error installing zip file", that is why. Nothing
> is wrong with your download.**
>
> This ROM uses **retrofit dynamic partitions**. Its installer calls
> `update_dynamic_partitions` and `map_partition`, which TWRP does not implement
> for retrofit devices — it aborts immediately with a generic error 1.
>
> Flash the `recovery.img` from [Releases](../../releases) first:
>
> ```
> fastboot flash recovery recovery.img
> ```
>
> then sideload the ROM from **LineageOS Recovery**. Full steps in
> [Flashing](#flashing) below.
>
> Two more things that surprise people, both normal:
> - **"System wipe failed" during factory reset is expected.** Before the first
>   install there is no super metadata to map, so system cannot be wiped. The line
>   that matters is `Data wipe complete.` Do not try to fix this — the ROM
>   installer creates that metadata itself.
> - **This repartitions your phone.** `system` + `oem` become a single 5.1 GB
>   `super`. A TWRP nandroid taken beforehand will **not** restore afterwards.
>   Download stock Motorola firmware *before* you start if you might want to go back.

An **unofficial** build of LineageOS 22.2 / Android 15 for the Motorola Moto G5S
Plus (`sanders`, XT1801–XT1806, msm8953 / Snapdragon 625), plus everything needed
to reproduce it.

Built 2026-08-01. Download from [Releases](../../releases).

```
lineage-22.2-20260801-UNOFFICIAL-sanders.zip
932 MB
sha256: e1fabd9763535fd08c398e6547860a07e05468cf848752b2e078491c7dadddb0
```

## Status — this is the first LOS 22 build for this device

As of August 2026 no LineageOS 22 build for sanders had ever been published. The
newest community artifact found anywhere was
`lineage-17.1-20230607-UNOFFICIAL-sanders.zip`. There is no community bug list
because there was no release.

**Confirmed working** on an XT1804 (this build, flashed 2026-08-02):
- Boots
- Camera works — despite `USE_CAMERA_STUB := true` in the device tree
- Retrofit to dynamic partitions succeeded from ArrowOS 11

**Untested / unknown:** fast charging (see patch 0002 below), VoLTE, Bluetooth,
NFC, fingerprint.

**Known by design:** SELinux ships **permissive**
(`BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive`, under a `# TMP - A13
Bring` comment in the device tree). Play Integrity will fail.

## ⚠️ Flashing repartitions your phone

This ROM uses **retrofit dynamic partitions**. Its installer runs
`update_dynamic_partitions`, which executes `remove_all_groups` and rebuilds your
physical `system` + `oem` partitions into a single 5.1 GB `super` containing five
logical partitions.

Consequences:

- **TWRP cannot install this ROM.** It does not implement `update_dynamic_partitions`
  / `map_partition` for retrofit devices and aborts with a generic **error 1**.
  Use LineageOS Recovery (`recovery.img`, attached to the release).
- **A TWRP nandroid backup taken beforehand will not restore** onto a super
  layout. Returning to a stock-layout ROM means flashing stock Motorola firmware
  via fastboot first. Have it downloaded before you start.

## Flashing

Sanders uses fastboot — no Odin, no tar repacking.

```bash
fastboot flash recovery recovery.img
# boot straight to recovery: Vol Down + Power -> Recovery
```

Then in LineageOS Recovery:

1. Factory reset → Format data/factory reset.
   **A "System wipe failed" error here is expected and harmless** — before the
   first install there is no super metadata to map, so system cannot be wiped.
   `Data wipe complete.` is the line that matters. Do not try to fix this; the
   install creates the metadata itself.
2. Apply update → Apply from ADB → `adb sideload lineage-22.2-...-sanders.zip`
3. Google apps, if wanted, in the **same session before first boot** —
   MindTheGapps **15** arm64 (not 14).
4. Reboot.

A successful install ends with `Install completed with status 0.` and
`/dev/block/mapper/` then contains `system`, `vendor`, `product`, `odm`,
`system_ext`.

## Building it yourself

Upstream is the [Sanders-Revived](https://github.com/Sanders-Revived) org. The
device tree is self-contained — there is **no** `msm8953-common` tree anywhere.

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs
mkdir -p .repo/local_manifests
cp local_manifest.xml .repo/local_manifests/sanders.xml
repo sync -c -j4
# apply patches/ (see below)
source build/envsetup.sh
breakfast sanders          # -> lunch lineage_sanders-bp1a-userdebug
mka -j16 bacon
```

To reproduce **this exact build**, use `manifest-snapshot.xml` instead — it pins
every project to the commit SHA used here:

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs
cp manifest-snapshot.xml .repo/manifests/
repo init -m manifest-snapshot.xml
repo sync -c -j4
```

`setup_sanders.sh` and `start_build.sh` automate the sync and build. Launch the
build with `setsid`, **not** as a plain background job:

```bash
setsid nohup bash start_build.sh >/dev/null 2>&1 </dev/null & disown
```

### Base branch is `lineage-22.2`, not 22.0 or 22.1

Two references in `device.mk` pin it, and both fail on the earlier branches:
`rfs_msm_mpss_readonly_vendor_fsg_symlink` and `libqsap_sdk` are defined in
`LineageOS/android_hardware_motorola` only from `lineage-22.2` onward. Corroborated
by `vendor/lineage/vars/aosp_target_release` = `bp1a` on 22.2 (vs `ap4a` on 22.1).

The device tree has **no `lineage.dependencies`**, so `breakfast sanders` pulls
nothing — the local manifest is mandatory. It also adds two repos absent from the
base manifest: `hardware/motorola`, and `system/tools/dtbtool` pinned at
`lineage-18.1` (it provides `dtbToolLineage`, required by
`BOARD_KERNEL_SEPARATED_DT := true`, and has not been in a LineageOS manifest
since LOS 18).

## Patches

### 0001 — protobuf vendorcompat

`device.mk` requires `libprotobuf-cpp-{full,lite}-3.9.1-vendorcompat`, which do
not exist on `lineage-22.2`. The upstream commit adding them to
`hardware/lineage/compat` is dated 2026-07-04 and landed on **`lineage-23.2`
only**; the sanders commit requiring them is from 2026-01-10 — six months earlier.
Reverted to the non-versioned variants, which are defined at
`hardware/lineage/compat/Android.bp:756` and `:775`.

### 0002 — kernel DTS `dpdm-supply` phandle (upstream bug)

**`Sanders-Revived/kernel_motorola_msm8953@4.9.337` does not build as committed.**

HEAD commit `3cc43241e392` ("dts: msm8953-sanders: fix quick charge (error -19) by
adding missing dpdm-supply", 2026-05-27) added:

```dts
&qpnp_smbcharger {
        dpdm-supply = <&usb_otg>;
```

`usb_otg` is the label for the ChipIdea `msm-otg` controller and is not defined
anywhere in the msm8953 include chain — every one of the ~30 `&usb_otg` references
in that dts directory belongs to an msm8916/8937/8917/8940/8909 file. **msm8953 is
a dwc3 part.** All four `msm8953-sanders-p*.dtb` targets fail with:

```
ERROR (phandle_references): Reference to non-existent node or label "usb_otg"
```

The commit's diagnosis was right — `qpnp-smbcharger-mmi-lite.c:1543` is literally
`return -ENODEV;`, the "error -19" in its message — only the phandle was wrong.
The fix points it at the node that actually provides the dpdm regulator:

```dts
-        dpdm-supply = <&usb_otg>;
+        dpdm-supply = <&qusb_phy>;
```

`qusb_phy` (`msm8953.dtsi:1819`) is `compatible = "qcom,qusb2phy"`, matched by
`drivers/usb/phy/phy-msm-qusb.c`, which registers the dpdm regulator at
`phy-msm-qusb.c:900-929`. `CONFIG_USB_MSM_OTG` is not in `sanders_defconfig`, so
`<&usb_otg>` could never have worked here. In-tree precedent for dwc3/qusb2 parts:
`pmi632.dtsi:316`, `pmi8998.dtsi:101`, `sdm670-pmic-overlay.dtsi:35`.

Verified at the DTB level — preprocessed, compiled with the tree's own `dtc`,
decompiled, and confirmed `dpdm-supply` resolves to `qusb@79000`.

**This patch is unverified on real hardware.** It should make quick charge work as
the maintainer intended, but that is reasoned from driver source, not observed.

Both patches live on repo-managed checkouts, so `repo sync` discards them.

## Build gotchas

- **ccache**: if it is not installed, do **not** set `USE_CCACHE=1` /
  `CCACHE_EXEC`. Soong prefixes every compile with it and all of them die with
  `/bin/sh: 1: /usr/bin/ccache: not found`. Verify with `which ccache` first.
- **No `set -u`** in build scripts — `build/envsetup.sh` references an unbound
  `TOP` and aborts under `nounset`, silently producing an `rc=127` no-op build
  that looks like it ran.
- **`setsid`, not `&`** — a plain background build dies to SIGHUP when the parent
  shell exits, ~80 s in, with no error in the log.
- **repo config cache**: `repo manifest` caches `~/.gitconfig` keyed on mtime, and
  the build sandbox mounts `/` read-only. If `~/.gitconfig` changed since the cache
  was written, the sandboxed step dies with
  `OSError: [Errno 30] Read-only file system`. Re-warm it outside the sandbox
  before building — `start_build.sh` does this automatically.
- **git-lfs must be installed** before `repo sync`, or the Chromium WebView
  prebuilts land as pointer stubs and the build fails much later with
  `zip: not a valid zip file`. `repo init --git-lfs` does nothing without the binary.

## Android 16?

Probably feasible. All upstream scaffolding for an msm8953 legacy device already
exists on `lineage-23.x` and `lineage-24.0`: `device/qcom/sepolicy-legacy-um`,
`hardware/lineage/compat`, and the CAF `audio`/`display`/`media` repos all have
`lineage-23.0/23.1/23.2-caf-msm8953` and `lineage-24.0-caf-msm8953` branches.

Missing is only a sanders device tree and vendor at `16.0` — Sanders-Revived stops
at `15.0`. Unlike legacy Exynos devices, sanders needs **no** compat patch set
(its 4.9 kernel has real eBPF and cgroup v2), so a port is a "bump and fix" job
rather than re-deriving dozens of hacks.

## Credits

All device, kernel and vendor work is by the
[Sanders-Revived](https://github.com/Sanders-Revived) maintainers. This repo
contains only build fixes, notes, and a compiled artifact.
