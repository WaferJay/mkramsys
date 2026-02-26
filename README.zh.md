# mkramsys

[English](README.md) | 中文

构建基于 RAM 的 Debian 系统。通过 debootstrap 构建最小化 rootfs，打包为
squashfs 镜像，启动后整个系统运行在内存中，使用 overlayfs 提供可写层。

系统从只读 squashfs 运行，可写层位于 tmpfs——所有修改存在于内存中，重启后消失。

## 快速开始

```bash
# 构建基础镜像
sudo ./mkramsys init

# 定制
sudo ./mkramsys install vim curl openssh-server
sudo ./mkramsys driver          # 自动检测并安装固件

# 生成最终 squashfs
sudo ./mkramsys build -o system.sqfs
```

使用 `build/boot/` 中的内核和 initramfs 启动：

```
linux /vmlinuz boot=ramsys ramsys.src=/dev/sda1 ramsys.dir=system.sqfs
initrd /initrd.img
```

## 依赖

- Root 权限
- `debootstrap`、`mksquashfs` (squashfs-tools)、`bash`
- `driver` 命令需要：`modinfo`、`modprobe`

## 命令

```
mkramsys [-w WORKSPACE] <command> [options]
```

| 命令      | 说明                                     |
|-----------|------------------------------------------|
| `init`    | 通过 debootstrap 构建基础系统，生成 base.sqfs |
| `driver`  | 检测宿主机固件需求，安装对应的固件包     |
| `install` | 向镜像中安装软件包                       |
| `shell`   | chroot 进入镜像                          |
| `build`   | 清理并生成最终 squashfs                  |
| `reset`   | 丢弃所有 overlay 修改                    |

全局选项 `-w DIR` 设置工作区目录（默认：`./build`）。

### init

```bash
sudo ./mkramsys init [--force] [--mirror URL] [--codename NAME] [--comp-level N]
```

通过 debootstrap 创建基础 Debian 镜像。安装内核、生成包含 ramsys 引导脚本的
initramfs、提取引导文件，然后清除内核并清理 rootfs 以缩减镜像体积。

| 选项           | 说明                                                   |
|----------------|--------------------------------------------------------|
| `--force`      | 重新初始化，丢弃所有先前状态                           |
| `--mirror`     | Debian 镜像源（默认：`https://deb.debian.org/debian/`）|
| `--codename`   | Debian 发行版代号（默认：`trixie`）                    |
| `--comp-level` | zstd 压缩级别（默认：`15`）                            |

### driver

```bash
sudo ./mkramsys driver
```

扫描宿主机的固件需求：

1. 已加载的内核模块（`/proc/modules`）——查询固件依赖
2. 硬件 modalias（`/sys/bus/*/devices/*/modalias`）——解析为模块后查询固件
3. CPU 厂商——选择 `amd64-microcode` 或 `intel-microcode`

通过 `apt-file` 将检测到的固件文件映射为 Debian 软件包并安装。自动启用
`non-free-firmware` 仓库。

### install

```bash
sudo ./mkramsys install [-f packages.txt] [PKG...]
```

通过 overlay 安装软件包，修改累积在工作区的 upper 目录中。

`-f FILE` 从文件读取包名（每行一个，支持 `#` 注释）。

### shell

```bash
sudo ./mkramsys shell [-c CMD] [-l] [SCRIPT [ARGS...]]
```

| 形式                  | 行为                           |
|-----------------------|--------------------------------|
| `shell`               | 交互式 bash                   |
| `shell -l`            | 登录 shell（加载 /etc/profile）|
| `shell -c "cmd"`      | 执行命令字符串                 |
| `shell script.sh`     | 将脚本复制进 chroot 并执行     |
| `shell script.sh arg` | 执行脚本并传递参数             |

### build

```bash
sudo ./mkramsys build [-o output.sqfs] [--comp-level N]
```

在 chroot 内和宿主机侧执行 `cleansys --full`，然后生成 squashfs 镜像。
默认输出：`$WORKSPACE/output.sqfs`。

| 选项           | 说明                           |
|----------------|--------------------------------|
| `-o FILE`      | 输出 squashfs 路径             |
| `--comp-level` | zstd 压缩级别（默认：`15`）    |

这是一个终结性操作——cleansys 的删除会写入 overlay upper。如需继续修改，
先执行 `reset`。

### reset

```bash
sudo ./mkramsys reset [--force]
```

删除 overlay upper 目录，丢弃 `init` 之后的所有修改。基础镜像不受影响。
`--force` 跳过确认提示。

## 工作区

所有状态保存在单一目录中（默认 `./build/`）：

```
build/
├── base.sqfs        # init 生成的基础镜像
├── boot/            # 内核 + initramfs
├── upper/           # overlay 修改（跨命令持久保存）
├── .work/           # overlay 工作目录
└── .mkramsys        # 工作区标记文件
```

overlay 修改在 `driver`、`install`、`shell` 命令间累积。squashfs 仅创建两次：
`init` 时（基础镜像）和 `build` 时（最终镜像），避免迭代定制过程中重复压缩。

工作区通过文件锁防止并发访问。

## 引导参数

initramfs 引导脚本（`boot=ramsys`）将 squashfs 文件复制到 RAM 中，并使用
overlayfs 挂载为根文件系统。

| 参数                 | 说明                                     |
|----------------------|------------------------------------------|
| `ramsys.src=`        | 源设备（如 `/dev/sda1`、`UUID=`）        |
| `ramsys.dir=`        | squashfs 文件在源设备上的路径            |
| `ramsys.src.fstype=` | 文件系统类型（省略则自动检测）           |
| `ramsys.src.flags=`  | 源设备的额外挂载选项                     |

## 分发

```bash
./build.sh              # 生成 dist/mkramsys（单文件，约 34KB）
./build.sh output.sh    # 自定义输出路径
```

构建脚本将所有源码打包为一个自包含脚本，资源文件内嵌其中，运行时无需外部文件。

## 许可证

[GPLv3](LICENSE)
