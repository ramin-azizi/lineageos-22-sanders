# Moto G5S Plus (sanders / XT1804) — LineageOS 22.2 (Android 15) build plan

Researched 2026-08-01. Device confirmed over adb: `ro.product.device = sanders`,
`Moto G (5S) Plus`, currently on ArrowOS 11, **bootloader unlocked**.

Android 15 is the ceiling for this phone. LineageOS upstream has `lineage-23.0`,
`23.1`, `23.2` and even `lineage-24.0` branches, but no sanders device tree exists
for any of them — `Sanders-Revived` stops at `15.0`, and no other org has touched
sanders since 2022. Going newer means forward-porting the device tree, blobs and a
4.9 kernel yourself.

## Upstream

Everything comes from the `Sanders-Revived` org (actively maintained; device tree
and kernel last pushed May 2026). The device tree is **self-contained** — there is
no `msm8953-common` tree, from LineageOS or anyone else.

- Device — https://github.com/Sanders-Revived/device_motorola_sanders/tree/15.0
- Vendor — https://github.com/Sanders-Revived/vendor_motorola_sanders/tree/15.0
- Kernel — https://github.com/Sanders-Revived/kernel_motorola_msm8953/tree/4.9.337

## Base branch: `lineage-22.2`

Not a guess. Two module references in `device.mk` pin it, and both fail on 22.0/22.1:

- `rfs_msm_mpss_readonly_vendor_fsg_symlink` (device.mk:311) — defined only in
  `LineageOS/android_hardware_motorola` on `lineage-22.2`+. On 22.1 that repo has
  `vendor_fsg_mountpoint` but not the fsg symlink; on 22.0 it has no `Android.bp`.
- `libqsap_sdk` (device.mk:429) — exists on 22.2+; on 22.1 the directory is
  `libqsap_shim` with no such module.

Corroborating: `vendor/lineage/vars/aosp_target_release` is `bp1a` on 22.2 (vs
`ap4a` on 22.1), and `BUILD_ID=BP1A.250505.005`.

There is **no `lineage.dependencies`** file on any branch of the device tree, so
`breakfast sanders` pulls nothing — `local_manifest.xml` here is mandatory.

## Blobs — no extraction needed

`vendor_motorola_sanders@15.0` has 1018 prebuilt files (~265 MiB), matching
`proprietary-files.txt` exactly. Do **not** run `extract-files.py`; those scripts
are for the maintainer to regenerate the tree.

Worth knowing: the blobs are a cross-device mix — most from stock Oreo
`OPSS28.65-36-11-4`, but ADSP/audio from a Moto **deen** Android 10 dump
`QPKS30.54-22-21`. A fresh extraction from your own XT1804 could not produce the
deen half, which is another reason to use the checked-in tree as-is.

## Two references that will NOT resolve on a stock 22.2 tree — fix before building

**(a) `libprotobuf-cpp-{full,lite}-3.9.1-vendorcompat`** (device.mk:296-298).
These exist nowhere in a `lineage-22.2` checkout. The upstream commit adding them
to `hardware/lineage/compat` is dated 2026-07-04 and landed on **`lineage-23.2`
only**; the sanders commit requiring them (`2b38ad7`) is dated 2026-01-10 — six
months earlier. Fix: revert `device.mk` to `libprotobuf-cpp-full-vendorcompat` /
`libprotobuf-cpp-lite-vendorcompat` (which do exist on 22.2). Low risk; only
escalate to cherry-picking the 23.2 commit if a blob genuinely needs the 3.9.1
soname.

**(b) `dtbToolLineage`.** `BoardConfig.mk` sets `BOARD_KERNEL_SEPARATED_DT := true`,
which pulls `dt.img` into `INTERNAL_BOOTIMAGE_ARGS`. But `dtbToolLineage` lives in
`LineageOS/android_system_tools_dtbtool`, whose newest branch is `lineage-18.1` and
which has not been in a LineageOS manifest since LOS 18. Already handled — it's in
`local_manifest.xml`. Without it, `boot.img` fails at link.

The existence of both gaps says this tree has **not** been built end-to-end against
a stock 22.2 manifest recently.

## Expected quality — read before committing hours

This is a bringup tree, not a hardened daily driver:

- **SELinux ships permissive.** `BoardConfig.mk` sets
  `SELINUX_IGNORE_NEVERALLOWS := true` and
  `BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive`, under a comment
  reading `# TMP - A13 Bring`. Play Integrity will fail.
- **`USE_CAMERA_STUB := true`** — treat camera status as unknown at best.
- Retrofit dynamic partitions on a non-A/B device (`super` retrofitted across the
  old `system` + `oem`). Do not hand-edit `BOARD_SUPER_PARTITION_SIZE`.
- `PRODUCT_SHIPPING_API_LEVEL := 25` — what lets an Android 15 build skip modern
  vendor-API requirements. Leave alone.
- **Nobody has published a LOS 22 sanders build.** Newest community artifact found
  anywhere is `lineage-17.1-20230607-UNOFFICIAL-sanders.zip`. No issues, no PRs,
  one fork on the device repo. There is no community bug list because there is no
  release — you will be first to hit whatever breaks.

## Build commands

```bash
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G
source build/envsetup.sh
breakfast sanders          # -> lunch lineage_sanders-bp1a-userdebug
mka bacon
```

Use **`userdebug`, not `user`** — `SELINUX_IGNORE_NEVERALLOWS := true` is rejected
in user builds. Output: `out/target/product/sanders/lineage-22.2-<date>-UNOFFICIAL-sanders.zip`.

Do not install a host JDK or set `JAVA_HOME`; `lineage-22.2` syncs
`prebuilts/jdk/jdk21` from AOSP.

### Likely first build failure after (a) and (b)

The kernel. `lineage-22.2` defaults to `clang-r536225` (LLVM 19), but the
maintainer's own `build.sh` uses `clang-r522817` (LLVM 18) — so this 4.9 kernel
will compile with a newer clang than was ever tested, under `LLVM=1 LLVM_IAS=1`.
If it fails, add to `BoardConfig.mk`:

```make
TARGET_KERNEL_CLANG_VERSION := r522817
```

`clang-r522817` is present in AOSP prebuilts on `android15-qpr2-release`, so this
needs no extra repo.

## Disk

| Item | Estimate |
|---|---|
| `.repo` | 80–100 GB |
| Working checkout | 90–110 GB |
| `out/` (one device) | 60–90 GB |
| ccache | 50 GB |
| **Total** | **~300–350 GB** |

`/mnt/rom-data` is 885G with ~618G free, so this fits alongside the zenlte tree.
Remember E: is thin-provisioned — the Windows-side physical free space is the real
ceiling, not what `df` reports.

## Sequencing

Sync only **after** the zenlte build produces its zip. Both trees share one
5400rpm spindle and the contention is superlinear — two builds ran concurrently on
2026-08-01 (10:42 and 11:11 logs overlap) and a ninja was OOM-killed.

## Build failures actually hit

### 1. `libprotobuf-cpp-*-3.9.1-vendorcompat` — fixed
As predicted above. Patch: `patches/0001-sanders-protobuf-vendorcompat-drop-3.9.1.patch`.

### 2. Kernel clang — did NOT happen
The "likely first build failure" prediction above was **wrong**. The 4.9 kernel
compiles cleanly with the `lineage-22.2` default `clang-r536225` under
`LLVM=1 LLVM_IAS=1` — `vmlinux`, `System.map`, `Image`, `Image.gz` all built.
Do **not** add `TARGET_KERNEL_CLANG_VERSION := r522817`; it is not needed.

### 3. DTB compile: `Reference to non-existent node or label "usb_otg"` — fixed
Build 2026-08-01 died at 175,401/192,924 (~90%), the only failure, in
`Building DTBs` for all four `msm8953-sanders-p{1,2,3,4}.dtb`.

**Root cause.** Kernel branch `4.9.337` HEAD commit `3cc43241e392`
("dts: msm8953-sanders: fix quick charge (error -19) by adding missing
dpdm-supply", 2026-05-27) added one line to
`arch/arm64/boot/dts/qcom/msm8953-sanders.dtsi:692`:

```dts
&qpnp_smbcharger {
	dpdm-supply = <&usb_otg>;
```

`usb_otg` is **not defined anywhere in the msm8953 include chain**
(`msm8953-sanders-p*.dts` → `msm8953-sanders.dtsi` → `msm8953.dtsi` +
`pmi8950.dtsi` + pinctrl/panel dtsi). It is the label for the ChipIdea
`msm-otg` controller used by msm8916/8937/8917/8940/8909 — every one of the
~30 `&usb_otg` references in this dts directory lives in a file for one of
those SoCs. msm8953 is a **dwc3** part: it has `usb3: ssusb@7000000`
(`msm8953.dtsi:1696`) and `qusb_phy: qusb@79000` (`msm8953.dtsi:1819`).
The maintainer copied the property from an msm8937/8917 dtsi without
adjusting the phandle, and evidently never rebuilt the DTBs.

**Fix.** Point it at the node that actually provides the `dpdm` regulator on
this SoC. Patch: `patches/0002-sanders-kernel-dts-dpdm-supply-qusb_phy.patch`

```dts
	dpdm-supply = <&qusb_phy>;
```

Evidence the intent is preserved, not just the build unblocked:

- `qusb_phy` has `compatible = "qcom,qusb2phy"`, matched by
  `drivers/usb/phy/phy-msm-qusb.c:1264`, built via `CONFIG_MSM_QUSB_PHY=y`
  (`arch/arm64/configs/sanders_defconfig:440`).
- That driver **is** the dpdm regulator provider: it registers one at
  `phy-msm-qusb.c:900-929` with `cfg.of_node = dev->of_node`, so a phandle to
  the `qusb_phy` node resolves to it.
- The consumer is `drivers/power/supply/qcom/qpnp-smbcharger-mmi-lite.c:1525`
  (`CONFIG_QPNP_SMBCHARGER_MMI_LITE=y`, `sanders_defconfig:339`). Line 1543 is
  literally `return -ENODEV;` when no dpdm regulator is found — **that is the
  "error -19" the commit message names**, so the commit's diagnosis was right
  and only its phandle was wrong.
- `CONFIG_USB_MSM_OTG` (which builds `phy-msm-usb.c`, the driver behind
  `usb_otg` nodes) is **not** enabled in `sanders_defconfig`. `<&usb_otg>`
  could never have worked here even if a node existed.
- In-tree precedent for dwc3/qusb2 parts: `pmi632.dtsi:316`
  `dpdm-supply = <&qusb_phy>`; `pmi8998.dtsi:101`, `sdm670-pmic-overlay.dtsi:35`,
  `qcs605-lc-pmic-overlay.dtsi:35` all use `<&qusb_phy0>` (multi-phy naming).
- Cross-checked independently with `codex exec`, which reached the same answer
  unprompted.

**Alternatives rejected.** (a) Reverting `3cc4324` outright — builds, but
reintroduces the `-ENODEV` quick-charge bug the commit was written to fix, for
no benefit once the correct phandle is known. (b) Adding a `usb_otg` node to
`msm8953.dtsi` — wrong hardware; msm8953 has no ChipIdea OTG block and the
driver isn't compiled. (c) Pulling from
`Sanders-Revived/kernel_devicetree_motorola-sanders` — see below.

**On the `kernel_devicetree_motorola-sanders` question.** The conclusion earlier
in this document that the repo is not needed **holds**. All three branches
(`dts/sanders/4.9/master`, `dts/sanders/4.9/wip`, `dts/sanders/stock/master`)
were checked: none of them define `usb_otg` and none contain any `dpdm-supply`
line at all. That repo is an older snapshot in a different layout
(`common/` + `sanders/`) and predates commit `3cc4324`; it would not have
supplied the missing node. The ROM kernel's dts directory is complete — the
bug is a bad phandle in a new commit, not a missing file.

## Build succeeded — 2026-08-01

With patches 0001 and 0002 applied, the build completed end to end:

```
#### build completed successfully (52:02 (mm:ss)) ####
Package Complete: out/target/product/sanders/lineage-22.2-20260801-UNOFFICIAL-sanders.zip
```

Artifacts in `src/out/target/product/sanders/`:

| File | Size |
|---|---|
| `lineage-22.2-20260801-UNOFFICIAL-sanders.zip` | 977,537,427 (932 MiB) |
| `boot.img` | 14,430,208 |
| `recovery.img` | 18,995,200 |
| `dt.img` | 985,088 |

`dt.img` is non-empty, which confirms `dtbToolLineage` (gap (b) above) resolved and
packed the four `msm8953-sanders-p*.dtb` files. This is, as far as can be
determined, the **first LineageOS 22 build of sanders that has ever completed** —
see "Nobody has published a LOS 22 sanders build" above. Nothing here has been
flashed or booted; everything under "Expected quality" still applies.

## Open questions

- Which branch the maintainer actually builds against (no CI for the ROM; the only
  GitHub Actions workflow builds an AnyKernel zip). `lineage-22.2` is a strong but
  indirect inference.
- Whether the protobuf 3.9.1 reference is known-broken or the maintainer carries an
  unpublished local patch.
- What actually works on-device. No release, no changelog, no "what's broken"
  section. Camera/fingerprint/VoLTE status all unknown.

## 2026-08-02 00:52 — BUILD COMPLETE

`out/target/product/sanders/lineage-22.2-20260801-UNOFFICIAL-sanders.zip`
932 MB (977,537,427 bytes), 0 errors.
sha256: e1fabd9763535fd08c398e6547860a07e05468cf848752b2e078491c7dadddb0

`lineage_sanders-ota.zip` is a hardlink to the same file (link count 2), not a
second artifact.

Also produced — this device DOES use fastboot (unlike the Samsung zenlte):
  - `recovery.img`  (19.0 MB)  -- LineageOS recovery from this same tree
  - `boot.img`      (14.4 MB)
  - `dt.img`        (985 KB)   -- proof the `system/tools/dtbtool` manifest entry
                                  was needed; BOARD_KERNEL_SEPARATED_DT produced it
  - `product.img`   (482 MB)
  - `odm.img`, `cache.img`, `super_empty.img`

Ninja graph: 192,924 targets. Final leg 22:58:26Z -> 00:52 (~1h54m) for the last
17,526 after the DTB fix.

### Three failures hit, all fixed
1. `/usr/bin/ccache: not found` at 0% (12 targets) — ccache is NOT installed on
   this machine; `CCACHE_EXEC` was set anyway. Removed from start_build.sh.
2. `libprotobuf-cpp-*-3.9.1-vendorcompat` — patches/0001.
3. DTB `usb_otg` phandle — patches/0002. An upstream bug in Sanders-Revived
   kernel HEAD `3cc43241e392`; their current tree does not build as committed.

### Predictions that were WRONG
- Kernel clang mismatch: never happened. 4.9 kernel builds fine on clang-r536225.
- `kernel_devicetree_motorola-sanders` being needed: it is not. Confirmed all
  three of its branches lack `usb_otg` and `dpdm-supply` entirely.

### Untested
Nobody has booted this. SELinux is permissive, `USE_CAMERA_STUB := true`, and the
dpdm-supply patch is unverified on real hardware.
