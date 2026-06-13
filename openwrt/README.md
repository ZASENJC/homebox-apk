# Homebox for OpenWrt 25+

This directory contains an OpenWrt SDK package definition for packaging Homebox
as an OpenWrt 25.12 and newer `.apk` package. OpenWrt 25.12 replaced `opkg`
with `apk`, but packages are still assembled through the normal OpenWrt SDK
package tree.

This is intended to be the independent OpenWrt APK branch for the
`ZASENJC/homebox-apk` fork. Keep long-lived APK work on
`codex/openwrt-25-apk` or a branch forked from it, and merge upstream Homebox
changes into that branch deliberately.

## 用户安装说明

普通用户不需要自己编译。请到
[ZASENJC/homebox-apk Releases](https://github.com/ZASENJC/homebox-apk/releases)
下载与你的 OpenWrt 目标平台匹配的 `.apk` 文件，然后上传到路由器安装。

常见文件对应关系：

- `homebox-openwrt-x86-64.apk`：x86 软路由、迷你主机、虚拟机
- `homebox-openwrt-mediatek-filogic.apk`：MT7981、MT7986、Filogic 设备
- `homebox-openwrt-bcm27xx-bcm2711.apk`：Raspberry Pi 4
- `homebox-openwrt-rockchip-armv8.apk`：Rockchip ARM64 设备
- `homebox-openwrt-qualcommax-ipq807x.apk`：Qualcomm IPQ807x 设备
- `homebox-openwrt-armsr-armv7.apk` / `homebox-openwrt-armsr-armv8.apk`：通用 ARM SystemReady 目标
- `homebox-openwrt-mvebu-cortexa53.apk` / `homebox-openwrt-mvebu-cortexa72.apk`：Marvell mvebu 目标

安装示例：

```sh
scp homebox-openwrt-x86-64.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1
apk add --allow-untrusted /tmp/homebox-openwrt-x86-64.apk
/etc/init.d/homebox enable
/etc/init.d/homebox start
```

默认监听 `0.0.0.0:3300`。启动后，在同一局域网访问
`http://路由器IP:3300` 即可使用 Homebox。

修改端口或监听地址：

```sh
uci set homebox.main.port='3300'
uci set homebox.main.host='0.0.0.0'
uci commit homebox
/etc/init.d/homebox reload
```

本包面向 OpenWrt 25+ 的 `apk` 包管理系统；旧版 `opkg` 系统不能直接安装这些 `.apk` 文件。

The fast build path intentionally does not use OpenWrt's `lang/rust` package
helper. That helper builds a target Rust/LLVM toolchain inside the SDK and is
too slow for routine branch CI. Instead, the script:

1. Builds the web assets with `pnpm`.
2. Cross-compiles the Rust server with rustup's musl target and the OpenWrt SDK
   target gcc linker.
3. Passes the resulting `homebox` binary to the SDK package as
   `HOMEBOX_PREBUILT`.
4. Lets the SDK produce the final `.apk` metadata and layout.

## Build

Install the OpenWrt 25.12+ SDK for your target. Build Homebox separately and
pass the binary to the package with `HOMEBOX_PREBUILT`:

Copy or symlink the package into the SDK:

```sh
mkdir -p package
cp -a /path/to/homebox-apk/openwrt/homebox package/homebox
```

Select and build the package:

```sh
make menuconfig
make package/homebox/compile V=s HOMEBOX_PREBUILT=/absolute/path/to/homebox
```

The SDK writes the resulting `.apk` under `bin/packages/<arch>/base/` or the
configured package output directory.

For normal use, prefer the helper script because it downloads the matching SDK,
builds the web assets, cross-compiles the binary, and packages the APK:

```sh
TARGET=x86 SUBTARGET=64 openwrt/scripts/build-apk-in-sdk.sh
```

## Local Docker Build

The official OpenWrt SDK is a Linux x86_64 toolchain. On macOS or other non-Linux
hosts, use the Docker wrapper:

```sh
TARGET=x86 SUBTARGET=64 openwrt/scripts/build-apk-docker.sh
```

The output is copied to `openwrt/dist/<target>-<subtarget>/`. Common examples:

```sh
TARGET=x86 SUBTARGET=64 openwrt/scripts/build-apk-docker.sh
TARGET=mediatek SUBTARGET=filogic openwrt/scripts/build-apk-docker.sh
TARGET=ipq40xx SUBTARGET=generic openwrt/scripts/build-apk-docker.sh
```

The SDK script limits build parallelism to 4 jobs by default; override it when
needed:

```sh
OPENWRT_BUILD_JOBS=2 TARGET=x86 SUBTARGET=64 openwrt/scripts/build-apk-docker.sh
```

## GitHub Actions Matrix

`.github/workflows/openwrt-apk.yml` builds the branch against OpenWrt 25.12.4 by
default and uploads one artifact per target. The current matrix covers common
OpenWrt install targets:

- `x86/64`
- `armsr/armv7`
- `armsr/armv8`
- `mediatek/filogic`
- `rockchip/armv8`
- `bcm27xx/bcm2711`
- `qualcommax/ipq807x`
- `ipq40xx/generic`
- `mvebu/cortexa53`
- `mvebu/cortexa72`

MIPS targets such as `ramips/mt7621` and `ath79/generic` are not in the fast
matrix because Rust 1.82 does not ship `mips*-unknown-linux-musl` standard
libraries through rustup. Supporting those targets requires a separate slow path
using OpenWrt's Rust feed or a custom nightly `build-std` toolchain.

## Install

Copy the built package to the router and install it:

```sh
apk add ./homebox-*.apk
/etc/init.d/homebox enable
/etc/init.d/homebox start
```

Homebox listens on `0.0.0.0:3300` by default. Runtime settings live in
`/etc/config/homebox`:

```sh
uci set homebox.main.port='3300'
uci set homebox.main.host='0.0.0.0'
uci commit homebox
/etc/init.d/homebox reload
```

Optional throughput tuning can be set with `workers`, `max_connections`, and
`keep_alive_secs`; these map directly to `homebox serve` flags.

## Firewall

Most default OpenWrt LAN zones already allow access from LAN clients. The
package also installs `/etc/firewall.homebox`, which can be used as a firewall
include for environments that explicitly filter LAN input. Set
`HOMEBOX_OPEN_FIREWALL=0` to disable that helper.
