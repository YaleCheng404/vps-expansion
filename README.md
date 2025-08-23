# VPS-Expansion

**Linux Universal Root Partition Expansion Tool**
**通用 Linux 根分区扩容工具**



## 📌 Description | 描述

VPS-Expansion is a safe and universal root partition expansion tool for Linux servers (VPS/Cloud/Physical). It automatically detects your root filesystem, expands the underlying partition using `growpart`, and then extends the filesystem (`resize2fs` for EXT, `xfs_growfs` for XFS).
Supports both **bare partitions** and **single-PV LVM** setups across mainstream Linux distributions.



VPS-Expansion 是一个安全、通用的 Linux 根分区扩容工具，适用于 VPS、云主机和物理服务器。它可自动识别根文件系统，利用 `growpart` 扩展分区，并根据文件系统类型（EXT 用 `resize2fs`，XFS 用 `xfs_growfs`）自动扩容。
支持 **裸分区** 和 **单物理卷 LVM**，兼容主流 Linux 发行版。



## 🖥 Supported Platforms | 支持平台

* CentOS / RHEL / AlmaLinux / RockyLinux
* Debian / Ubuntu / Kali / Deepin
* openSUSE / SUSE Linux Enterprise
* Alpine Linux
* Arch Linux / Manjaro
* 其他大多数基于 Linux 的发行版（需支持 `growpart`）



## ⚙ Features | 功能特点

* **Auto Detection | 自动检测** — 自动识别根分区设备
* **Cross-Distro Support | 跨发行版支持** — 适配 `apt`、`yum`、`dnf`、`zypper`、`apk`、`pacman`
* **No Downtime for Root FS | 根分区在线扩容** — 支持在线扩展已挂载的根分区
* **Filesystem-aware | 文件系统自适应** — 自动选择 EXT 或 XFS 对应扩容命令
* **LVM Support | LVM 支持** — 支持单PV LVM自动扩容
* **Dry Run Mode | 预演模式** — `--dry-run` 模式可预览即将执行的操作
* **Fail-safe | 风险控制** — 对多PV LVM、Btrfs 等复杂场景直接中止并提示人工处理



## 📥 Installation | 安装

```bash
wget -O expansion.sh https://raw.githubusercontent.com/YaleCheng404/vps-expansion/refs/heads/master/expansion.sh
chmod +x expansion.sh
```



## 🚀 Usage | 使用方法

### 1. Basic Expansion | 基础扩容

```bash
sudo bash expansion.sh
```

Automatically detects and expands `/` root partition.
自动检测并扩容 `/` 根分区。

### 2. Dry Run Mode (No changes) | 预演模式（不做修改）

```bash
sudo bash expansion.sh --dry-run
```

Preview actions without making changes.
只预览，不执行任何修改操作。

### 3. Specify Target Device | 指定目标分区

```bash
sudo bash expansion.sh --device /dev/sdb1
```

Force expansion on a specific partition (use with caution).
对指定分区执行扩容（谨慎使用）。



## 📌 Parameters | 参数说明

| Parameter / 参数   | Description / 说明                           |
| ---------------- | ------------------------------------------ |
| `--dry-run`      | Preview only, no actual changes / 仅预览操作不执行 |
| `--device <dev>` | Manually specify target device / 手动指定扩容设备  |



## ⚠ Precautions | 注意事项

1. Ensure you have **increased disk size** in cloud provider/VM manager before running this tool.
2. Backup important data before resizing.
3. For multi-PV LVM, RAID, encrypted disks, this script will stop and prompt manual handling.



1. 请先在云厂商控制台或虚拟化平台 **调整磁盘大小**，再运行本工具。
2. 扩容前务必备份重要数据。
3. 对于多PV LVM、RAID、加密盘等复杂结构，本脚本会中止并提示人工处理。



## 📜 Example Output | 输出示例

```text
[INFO] Target: /dev/vda1
[INFO] Expanding partition with growpart...
[INFO] Expanding ext filesystem with resize2fs...
[SUCCESS] Expansion completed!
```



## 📄 License | 许可证

GPL-3.0 License
You may copy, distribute, and modify the software as long as you track changes/dates in source files, disclose source, and license derivatives under GPL-3.0.
您可以复制、分发和修改本软件，但必须在源文件中注明更改和日期，公开源代码，并且衍生作品必须采用 GPL-3.0 许可证。
