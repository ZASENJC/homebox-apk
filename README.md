# Homebox OpenWrt 25 APK

Homebox 是一个家庭网络工具箱，用于在家庭局域网内做 Ping、下载、上传和持续压测。本仓库面向 OpenWrt 25+ 用户提供可直接安装的 `.apk` 包，让 Homebox 可以直接跑在软路由或 OpenWrt 路由器上。

OpenWrt 25 及更新版本使用 `apk` 包管理器。如果你的系统仍然使用 `opkg`，这些 `.apk` 文件不能直接安装。

[下载 OpenWrt APK Release](https://github.com/ZASENJC/homebox-apk/releases/tag/openwrt-apk-v0.1.1)

![dark-theme](./doc/dark-theme.png)

![light-theme](./doc/light-theme.png)

## 下载安装

在 Release 页面下载与你路由器目标平台匹配的文件。文件名中的目标平台要和 OpenWrt 的 target/subtarget 对应。

| OpenWrt 设备类型 | 下载文件 |
| --- | --- |
| x86 软路由、迷你主机、虚拟机 | `homebox-openwrt-x86-64.apk` |
| MT7981、MT7986、Filogic 设备 | `homebox-openwrt-mediatek-filogic.apk` |
| Raspberry Pi 4 | `homebox-openwrt-bcm27xx-bcm2711.apk` |
| Rockchip ARM64 设备 | `homebox-openwrt-rockchip-armv8.apk` |
| Qualcomm IPQ807x 设备 | `homebox-openwrt-qualcommax-ipq807x.apk` |
| IPQ40xx 设备 | `homebox-openwrt-ipq40xx-generic.apk` |
| 通用 ARM SystemReady 32 位 | `homebox-openwrt-armsr-armv7.apk` |
| 通用 ARM SystemReady 64 位 | `homebox-openwrt-armsr-armv8.apk` |
| Marvell mvebu Cortex-A53 | `homebox-openwrt-mvebu-cortexa53.apk` |
| Marvell mvebu Cortex-A72 | `homebox-openwrt-mvebu-cortexa72.apk` |

不知道设备目标平台时，可以在路由器上查看：

```sh
ubus call system board
```

安装示例：

```sh
scp homebox-openwrt-x86-64.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1
apk add --allow-untrusted /tmp/homebox-openwrt-x86-64.apk
/etc/init.d/homebox enable
/etc/init.d/homebox start
```

启动后，在同一局域网内访问：

```text
http://路由器IP:3300
```

## 使用方式

Homebox 默认监听 `0.0.0.0:3300`，局域网设备用浏览器打开页面即可测试。

- 单次测速：依次执行 Ping、Download、Upload，适合日常检查链路速度。
- 持续压测：持续以高负载压测链路，适合测试无线漫游、路由器转发稳定性、多设备并发或散热表现。
- 低速模式：默认模式，适合千兆或 2.5G 以下网络，资源占用较低。
- 高速模式：适合 10G 及以上网络，会更激进地使用客户端 CPU 和浏览器资源。

测速结果受客户端性能影响明显。万兆以上网络测试时，客户端 CPU 单核性能、浏览器版本和网卡性能都可能成为瓶颈。

## 配置

运行配置保存在 `/etc/config/homebox`。

修改监听端口：

```sh
uci set homebox.main.port='3300'
uci commit homebox
/etc/init.d/homebox reload
```

修改监听地址：

```sh
uci set homebox.main.host='0.0.0.0'
uci commit homebox
/etc/init.d/homebox reload
```

查看服务状态：

```sh
/etc/init.d/homebox status
```

查看运行参数：

```sh
uci show homebox
```

卸载：

```sh
/etc/init.d/homebox stop
/etc/init.d/homebox disable
apk del homebox
```

## 防火墙

多数 OpenWrt 默认 LAN 区域允许局域网设备访问路由器服务。如果浏览器打不开 `http://路由器IP:3300`，先检查：

```sh
/etc/init.d/homebox status
netstat -ltnp | grep 3300
```

包内安装了 `/etc/firewall.homebox`，供需要显式放行 LAN 侧 TCP 3300 的环境使用。复杂防火墙环境中，请确认 LAN 到路由器本机的 3300 端口没有被规则拦截。

## 校验下载

Release 页面提供 `SHA256SUMS.txt`。下载 APK 后可以校验：

```sh
sha256sum -c SHA256SUMS.txt
```

如果只下载了单个 APK，可以直接对比：

```sh
sha256sum homebox-openwrt-x86-64.apk
```

## 支持的目标

当前 Release 已构建并上传以下 OpenWrt 25.12.4 目标：

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

MIPS 目标，例如 `ramips/mt7621` 和 `ath79/generic`，当前没有放进快速构建矩阵。这类目标需要单独处理 Rust 标准库和 OpenWrt Rust 工具链，不能直接复用本仓库当前的快速构建方式。

## 常见问题

### 安装时报 `apk: not found`

你的系统不是 OpenWrt 25+，或者当前固件仍然使用 `opkg`。本仓库发布的是 OpenWrt 25+ 的 `.apk` 包，不能直接安装到旧版 `opkg` 系统。

### 页面打不开

先确认服务正在运行：

```sh
/etc/init.d/homebox status
```

再确认端口在监听：

```sh
netstat -ltnp | grep 3300
```

如果服务和端口都正常，检查浏览器访问的 IP 是否是路由器 LAN IP，并确认防火墙没有拦截 LAN 侧 TCP 3300。

### 应该下载 `linux-amd64` 还是这个 APK

OpenWrt 通常是 musl libc 环境，普通 Linux glibc 二进制不一定能运行。本仓库的 APK 会使用面向 OpenWrt/musl 的构建产物，并安装 init 脚本和默认 UCI 配置。OpenWrt 25+ 用户优先下载本仓库的 `homebox-openwrt-*.apk`。

### 测速达不到预期

Homebox 是浏览器测速工具，客户端性能会影响结果。高速模式会占用更多 CPU 和浏览器资源；如果只是测试千兆或 2.5G 网络，默认低速模式通常更稳定。

## 面向开发者

构建脚本、OpenWrt 包定义和目标矩阵说明在 [openwrt/README.md](./openwrt/README.md)。

本仓库的 OpenWrt APK workflow 会为常见目标生成 artifacts。普通用户优先使用 Release 页面，不需要自己编译。

## 原项目

上游项目：[XGHeaven/homebox](https://github.com/XGHeaven/homebox)

原仓库 README：[XGHeaven/homebox README](https://github.com/XGHeaven/homebox/blob/master/README.md)

Homebox 使用 Rust(actix-web) 编写服务端，前端使用 TypeScript、React 和 Rspack。
