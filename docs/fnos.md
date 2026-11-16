# 飞牛（fnOS）安装包

本仓库是 [guohuiyuan/go-music-dl](https://github.com/guohuiyuan/go-music-dl) 的 fork，在保留上游代码的同时，把上游的 Linux 构建重新打包成飞牛（fnOS）原生应用（`.fpk`），并由 GitHub Actions 自动跟随上游 release 更新。

## 安装

1. 打开本仓库的 [Releases](https://github.com/jiu-zui-90817/go-music-dl/releases) 页面，下载最新 `fnos-v*` 版本中对应架构的安装包：
   - `go-music-dl_<version>_x86.fpk`：x86_64（amd64）飞牛设备
   - `go-music-dl_<version>_arm.fpk`：ARM64（arm64）飞牛设备
2. 在飞牛 OS 中进入「应用中心 → 设置 → 手动安装应用」，选择下载好的 `.fpk`。
3. 安装完成后从桌面图标打开，或直接访问 `http://NAS:8090/music/`。

首次启动时，管理员初始化用的 `Web setup token` 会写入应用日志，可通过「应用中心 → Go Music DL → 运行日志」查看；也可以 ssh 到 NAS 执行 `cmd/main log`。

## 运行时约定

| 项目 | 值 |
| --- | --- |
| appname | `go-music-dl` |
| 服务端口 | `8090`（manifest `service_port`，与 `GoMusicDL.sc` 端口映射一致） |
| 访问路径 | `/music/`（程序内置 Web 基础路径） |
| 安装目录 | `TRIM_APPDEST`（`/var/apps/go-music-dl/target`） |
| 数据目录 | `TRIM_PKGVAR`（`/vol*/@appdata/go-music-dl`） |
| 日志 | `${TRIM_PKGVAR}/go-music-dl.log` |
| 运行用户 | `go-music-dl`（`config/privilege` 中 `run-as: package`） |

`cmd/main` 负责 `start` / `stop` / `status` / `log`：启动时以数据目录作为工作目录，执行 `bin/music-dl web --port $TRIM_SERVICE_PORT --no-browser --base-path /music`，并把 PID 写入数据目录。数据库、下载文件等运行时数据因此都落在应用数据目录中，升级不会丢失。下载目录可在 Web 设置页改成任意有权限的共享文件夹（例如 `/vol1/音乐`）。

### 目录结构

```text
fnos/
├── manifest                 # 应用名、版本、端口、平台等
├── cmd/
│   ├── main                 # 启停入口（start/stop/status/log）
│   └── install_init ...     # 生命周期钩子（本应用为无操作脚本）
├── config/
│   ├── privilege            # 运行用户/用户组
│   └── resource             # 端口映射文件声明
├── ui/
│   ├── config               # 桌面入口（http://NAS:8090/music/）
│   └── images/icon-{64,256}.png
├── ICON.PNG / ICON_256.PNG  # 64 / 256 图标
└── GoMusicDL.sc             # 端口转发声明
```

`.fpk` 本身是 tar.gz：`app.tgz`（内含 `bin/music-dl`）+ `manifest`（记录 `app.tgz` 的 md5 `checksum`）+ `cmd/` + `config/` + `ui/` + 图标 + `.sc`。构建脚本会在打包后重新计算并校验 `app.tgz` 的 md5。

## 自动打包工作流

工作流文件：[`.github/workflows/fnos-package.yml`](../.github/workflows/fnos-package.yml)

- **定时同步**：每 6 小时查询一次上游 `releases/latest`；若本仓库已存在同名 `fnos-v<version>` release 则直接跳过。
- **手动触发**：Actions → fnOS Package → Run workflow，可填写上游版本（如 `v1.1.7`）重新打包。
- **tag 触发**：推送 `fnos-v<version>` tag 时按该版本打包。

流程：解析上游版本 → 下载 `go-music-dl_linux_{amd64,arm64}.tar.gz` → 生成 `app.tgz` → 打出 x86 / arm 两个 `.fpk` → 创建 `fnos-v<version>` release 并上传产物。

> fork 仓库的定时工作流默认处于禁用状态：首次使用时请在仓库 **Actions** 页点击 “I understand my workflows, go ahead and enable them”，或直接手动 Run workflow 一次。

## 本地构建

需要 bash、tar、gzip、md5sum（Linux / macOS / Git Bash 均可）：

```bash
# 1. 准备上游 release（示例为 v1.1.7 的 linux amd64 构建）
gh release download v1.1.7 -R guohuiyuan/go-music-dl -p 'go-music-dl_linux_amd64.tar.gz' -D build

# 2. 生成 app.tgz 与 fpk
bash scripts/build-app-tgz.sh build/go-music-dl_linux_amd64.tar.gz build/app-x86.tgz
bash scripts/build-fpk.sh 1.1.7 x86 build/app-x86.tgz dist
# 产物：dist/go-music-dl_1.1.7_x86.fpk
```

ARM 设备把 `amd64` 换成 `arm64`、`x86` 换成 `arm` 即可。

## 目录结构与「应用入口」要点

飞牛（fnOS）在安装时**从 app.tgz 载荷内部**读取应用入口配置，而不是从 fpk 根目录的 `ui/`：

```
app.tgz
├── bin/music-dl
├── README.md
├── LICENSE
└── ui/                 # 入口必须在这里（安装后为 ${TRIM_APPDEST}/ui）
    ├── config          # ".url" 入口定义，ID 需以 appname 前缀
    └── images/
        ├── icon_64.png
        └── icon_256.png
```

- `fnos/ui/config` 中的入口 ID 必须与 `fnos/manifest` 的 `desktop_applaunchname` 一致（本包均为 `go-music-dl.Application`）。
- 入口图标模板 `images/icon_{0}.png` 会被替换成 64 / 256，因此图标文件名固定为 `icon_64.png`、`icon_256.png`。
- `scripts/build-app-tgz.sh` 会把 `fnos/ui` 复制进载荷；`scripts/build-fpk.sh` 打包后会重新解出 app.tgz 并校验 `ui/config`、图标与二进制是否存在，缺失直接报错，避免再产出「能装能跑但没有入口」的包。

## 常见问题

**装好后只有「停用」按钮，桌面和应用中心都没有入口？**
1.1.7-1 之前的包把 `ui/config` 只放在 fpk 根目录，机关没有生效，已修复。请卸载旧版后重新安装 `go-music-dl_1.1.7-1_*.fpk`（或在应用中心直接覆盖安装同架构新包）；若入口仍未出现，重启一次 NAS 让应用中心刷新入口缓存。

**端口冲突**：默认 8090，若被占用请先停用占用该端口的应用；需要换端口可改 `fnos/manifest` 的 `service_port`、`fnos/ui/config` 的 `port` 与 `fnos/GoMusicDL.sc` 后重新打包。

## 打包修订号

同一上游版本需要重新打包（例如修复打包脚本）时，给版本加 `-N` 修订后缀即可：

```
Actions → fnOS Package → Run workflow → version = 1.1.7-2
```

上游 tag 会自动取 `-` 之前的部分（`v1.1.7`）下载产物，生成的 release 为 `fnos-v1.1.7-2`，manifest 版本为 `1.1.7-2`。

