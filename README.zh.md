# mkramsys

[English](README.md) | 中文

构建基于 RAM 的 Debian 系统。通过 debootstrap 构建最小化 rootfs，打包为
squashfs 镜像，启动后整个系统运行在内存中，使用 overlayfs 提供可写层。

系统从只读 squashfs 运行，可写层位于 tmpfs——所有修改存在于内存中，重启后消失。

## 快速开始

```bash
# 构建基础镜像
sudo ./mkramsys init -o base.sqfs

# 打开会话进行定制
sudo ./mkramsys open base.sqfs
sudo ./mkramsys install vim curl openssh-server
sudo ./mkramsys driver          # 自动检测并安装固件

# 生成最终 squashfs 并关闭会话
sudo ./mkramsys commit -o system.sqfs
```

使用 `boot/` 中的内核和 initramfs 启动：

```
linux /vmlinuz boot=ramsys ramsys.src=/dev/sda1 ramsys.dir=system.sqfs
initrd /initrd.img
```

## 依赖

- Root 权限
- `debootstrap`、`mksquashfs` (squashfs-tools)、`bash`
- `open` 命令需要：`unsquashfs` (squashfs-tools)
- `driver` 命令需要：`modinfo`、`modprobe`

## 命令

```
mkramsys [-w DIR] <command> [options]
```

| 命令      | 说明                                     |
|-----------|------------------------------------------|
| `init`    | 创建独立的 Debian squashfs 镜像          |
| `open`    | 在已有 squashfs 上启动会话               |
| `driver`  | 检测宿主机固件需求，安装对应的固件包     |
| `install` | 向镜像中安装软件包                       |
| `shell`   | chroot 进入镜像                          |
| `build`   | 快照当前状态为 squashfs（非破坏性）      |
| `commit`  | 终结：cleansys + squashfs + 关闭会话     |
| `reset`   | 丢弃 overlay 修改（保留会话）            |
| `close`   | 删除整个会话                             |

全局选项 `-w DIR` 覆盖自动会话发现，指定明确的会话目录。

### init

```bash
sudo ./mkramsys init -o <output.sqfs> [--boot-dir DIR] [--mirror URL] [--codename NAME] [--comp-level N]
```

通过 debootstrap 创建独立的 Debian squashfs 镜像。安装内核、生成包含 ramsys
引导脚本的 initramfs、提取引导文件，然后清除内核并清理 rootfs 以缩减镜像体积。

不会创建会话——这是一个纯粹的镜像构建器。

| 选项           | 说明                                                   |
|----------------|--------------------------------------------------------|
| `-o FILE`      | 输出 squashfs 路径（必填）                             |
| `--boot-dir`   | 内核 + initramfs 目录（默认：输出文件旁的 `boot/`）    |
| `--mirror`     | Debian 镜像源（默认：`https://deb.debian.org/debian/`）|
| `--codename`   | Debian 发行版代号（默认：`trixie`）                    |
| `--comp-level` | zstd 压缩级别（默认：`15`）                            |

### open

```bash
sudo ./mkramsys open <sqfs-path> [--force]
```

在已有 squashfs 文件上启动会话。创建会话目录（默认在 `/tmp`，可用 `-w` 覆盖），
并在当前目录写入 `.mkramsys-session`，后续命令自动找到该会话。

| 选项      | 说明                   |
|-----------|------------------------|
| `--force` | 覆盖已存在的活跃会话   |

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

通过 overlay 安装软件包，修改累积在会话的 upper 目录中。

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
sudo ./mkramsys build -o <output.sqfs> [--comp-level N]
```

将当前 overlay 状态快照为 squashfs 镜像，不执行 cleansys。会话保持活跃，
可继续修改。

| 选项           | 说明                           |
|----------------|--------------------------------|
| `-o FILE`      | 输出 squashfs 路径（必填）     |
| `--comp-level` | zstd 压缩级别（默认：`15`）    |

### commit

```bash
sudo ./mkramsys commit -o <output.sqfs> [--comp-level N]
```

在 chroot 内和宿主机侧执行 `cleansys --full`，生成最终 squashfs 镜像，
然后关闭会话。这是一个终结性操作——会话目录和 `.mkramsys-session` 都会被删除。

| 选项           | 说明                           |
|----------------|--------------------------------|
| `-o FILE`      | 输出 squashfs 路径（必填）     |
| `--comp-level` | zstd 压缩级别（默认：`15`）    |

### reset

```bash
sudo ./mkramsys reset [--force]
```

删除 overlay upper 目录，丢弃 `open` 之后的所有修改。源镜像和会话不受影响。
`--force` 跳过确认提示。

### close

```bash
sudo ./mkramsys close [--force]
```

删除会话目录和 `.mkramsys-session` 标记，丢弃所有 overlay 修改。
`--force` 跳过确认提示。

## 会话

镜像创建（`init`）和镜像修改（`open`/`commit`/`close`）是分离的：

```bash
# 创建 → 打开 → 修改 → 终结
sudo ./mkramsys init -o base.sqfs
sudo ./mkramsys open base.sqfs
sudo ./mkramsys install vim
sudo ./mkramsys commit -o final.sqfs

# 或者：快照但不关闭，继续工作
sudo ./mkramsys open base.sqfs
sudo ./mkramsys install vim
sudo ./mkramsys build -o snapshot.sqfs    # 会话保持活跃
sudo ./mkramsys install curl
sudo ./mkramsys commit -o final.sqfs      # cleansys + 关闭
```

会话发现机制：`open` 在当前目录写入 `.mkramsys-session`，后续命令读取此文件
找到会话。使用 `-w DIR` 可覆盖为指定路径。

会话目录结构：

```
/tmp/mkramsys-session.XXXXXX/
├── .mkramsys        # 会话标记
├── .source          # 源 squashfs 的绝对路径
├── .lock            # flock 目标
├── upper/           # overlay 修改（跨命令持久保存）
└── .work/           # overlay 工作目录
```

通过文件锁防止同一会话的并发访问。

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
./build.sh              # 生成 dist/mkramsys（单文件，约 42KB）
./build.sh output.sh    # 自定义输出路径
```

构建脚本将所有源码打包为一个自包含脚本，资源文件内嵌其中，运行时无需外部文件。

## 许可证

[GPLv3](LICENSE)
