#!/usr/bin/env bash
# Description: 通用 Linux 根分区扩容工具（支持裸分区与单PV LVM）
# Usage:
#   bash expand_root.sh                 # 自动扩容根分区
#   bash expand_root.sh --dry-run       # 只打印将执行的操作
#   bash expand_root.sh --device /dev/sdb1  # 指定要扩容的分区（谨慎！）
# Notes:
#   - 适配 apt / yum / dnf / zypper / apk / pacman
#   - 裸分区：growpart + resize2fs/xfs_growfs
#   - LVM（单PV）：growpart + pvresize + lvextend -r
#   - 不支持多PV聚合的VG（需人工确认）
#   - 建议先确保云盘/块设备已在云厂商侧扩容完成

set -euo pipefail

LOCKfile="/root/.$(basename "$0").lock"
LOGfile="/root/.$(basename "$0").log"
DRY_RUN=0
TARGET_PART=""

# ---------- Logging ----------
echo_log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts=$(date "+%Y-%m-%d %H:%M:%S")
  local color="\033[1;37m"
  case "$level" in
    success) color="\033[1;32m" ;;
    error)   color="\033[1;31m" ;;
    warn)    color="\033[1;33m" ;;
    info)    color="\033[1;34m" ;;
  esac
  echo -e "${color}${msg}\033[0m"
  echo "${ts} [$level] ${msg}" >> "$LOGfile"
}

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo_log info "[dry-run] $*"
  else
    echo_log info "执行: $*"
    eval "$@"
  fi
}

# ---------- Lock & Privilege ----------
check_lock() {
  if [[ -f "$LOCKfile" ]]; then
    echo_log error "操作已在进行中。若需强制运行，请删除: $LOCKfile"
    exit 1
  fi
  touch "$LOCKfile"
}
release_lock() { rm -f "$LOCKfile" || true; }
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo_log error "请使用 root 运行。"
    exit 1
  fi
}

# ---------- Args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --device)  TARGET_PART="${2:-}"; shift 2 ;;
    *) echo_log error "未知参数: $1"; exit 1 ;;
  esac
done

# ---------- PM detection ----------
PM=""
install_pkgs() {
  local pkgs=("$@")
  case "$PM" in
    apt)
      run "apt-get update -y"
      run "DEBIAN_FRONTEND=noninteractive apt-get install -y ${pkgs[*]}"
      ;;
    yum)   run "yum install -y ${pkgs[*]}" ;;
    dnf)   run "dnf install -y ${pkgs[*]}" ;;
    zypper) run "zypper --non-interactive in ${pkgs[*]}" ;;
    apk)   run "apk add --no-cache ${pkgs[*]}" ;;
    pacman) run "pacman -Sy --noconfirm ${pkgs[*]}" ;;
    *)
      echo_log warn "未识别的包管理器，跳过自动安装：${pkgs[*]}"
      ;;
  esac
}

detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then PM="apt"
  elif command -v yum >/dev/null 2>&1; then PM="yum"
  elif command -v dnf >/dev/null 2>&1; then PM="dnf"
  elif command -v zypper >/dev/null 2>&1; then PM="zypper"
  elif command -v apk >/dev/null 2>&1; then PM="apk"
  elif command -v pacman >/dev/null 2>&1; then PM="pacman"
  else PM=""
  fi
}

# ---------- Prereqs ----------
ensure_tools() {
  detect_pm

  # growpart（cloud-utils-growpart/cloud-guest-utils）
  if ! command -v growpart >/dev/null 2>&1; then
    case "$PM" in
      apt)    install_pkgs cloud-guest-utils ;;
      yum|dnf) install_pkgs cloud-utils-growpart ;;
      zypper) install_pkgs cloud-utils ;;
      apk)    install_pkgs cloud-utils-growpart util-linux ;;
      pacman) install_pkgs cloud-utils ;;
      *) echo_log warn "缺少 growpart，可能无法在线扩分区。请手动安装 cloud-utils-growpart/cloud-guest-utils。"
    esac
  fi

  # 基础工具
  for bin in lsblk findmnt blkid; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      install_pkgs util-linux
      break
    fi
  done

  # 文件系统工具
  if ! command -v resize2fs >/dev/null 2>&1; then
    case "$PM" in
      apt) install_pkgs e2fsprogs ;;
      yum|dnf) install_pkgs e2fsprogs ;;
      zypper) install_pkgs e2fsprogs ;;
      apk) install_pkgs e2fsprogs ;;
      pacman) install_pkgs e2fsprogs ;;
    esac
  fi
  if ! command -v xfs_growfs >/dev/null 2>&1; then
    case "$PM" in
      apt) install_pkgs xfsprogs ;;
      yum|dnf) install_pkgs xfsprogs ;;
      zypper) install_pkgs xfsprogs ;;
      apk) install_pkgs xfsprogs ;;
      pacman) install_pkgs xfsprogs ;;
    esac
  fi

  # LVM 工具（如需）
  if command -v lvs >/dev/null 2>&1; then
    : # ok
  else
    case "$PM" in
      apt) install_pkgs lvm2 ;;
      yum|dnf) install_pkgs lvm2 ;;
      zypper) install_pkgs lvm2 ;;
      apk) install_pkgs lvm2 ;;
      pacman) install_pkgs lvm2 ;;
    esac
  fi
}

# ---------- Helpers ----------
# 输入 /dev/sda1 或 /dev/nvme0n1p1 -> 输出：disk=/dev/sda part=1  或 disk=/dev/nvme0n1 part=1
split_disk_part() {
  local part="$1"
  local disk=""
  local pnum=""
  if [[ "$part" =~ ^/dev/nvme[0-9]+n[0-9]+p([0-9]+)$ ]]; then
    pnum="${BASH_REMATCH[1]}"
    disk="${part%p${pnum}}"
  elif [[ "$part" =~ ^(/dev/[a-z]+)([0-9]+)$ ]]; then
    disk="${BASH_REMATCH[1]}"
    pnum="${BASH_REMATCH[2]}"
  else
    # 更稳妥：用lsblk反查
    local pk
    pk=$(lsblk -no PKNAME "$part" 2>/dev/null || true)
    if [[ -n "$pk" ]]; then
      disk="/dev/$pk"
      # 再解析分区号
      pnum=$(lsblk -no PARTNUM "$part" 2>/dev/null || true)
    fi
  fi
  echo "$disk" "$pnum"
}

is_lvm_lv() {
  local src="$1"
  [[ "$src" =~ ^/dev/mapper/ ]] || [[ "$src" =~ ^/dev/.+/.+ ]] # /dev/mapper/vg-lv 或 /dev/<vg>/<lv>
}

# ---------- Core ----------
expand_plain_partition() {
  local part_dev="$1"
  local fs_type
  fs_type=$(blkid -o value -s TYPE "$part_dev" || true)
  if [[ -z "$fs_type" ]]; then
    echo_log error "无法识别文件系统类型：$part_dev"
    exit 1
  fi

  read -r disk pnum < <(split_disk_part "$part_dev")
  if [[ -z "$disk" || -z "$pnum" ]]; then
    echo_log error "无法解析磁盘与分区号：$part_dev"
    exit 1
  fi

  echo_log info "使用 growpart 扩展分区：磁盘=$disk 分区号=$pnum"
  if ! command -v growpart >/dev/null 2>&1; then
    echo_log error "缺少 growpart，无法在线扩分区。"
    exit 1
  fi
  run "growpart $disk $pnum"

  # 触发内核重读分区表（某些内核需要）
  run "partprobe $disk || true"
  run "udevadm settle || true"
  sleep 2

  case "$fs_type" in
    ext2|ext3|ext4)
      echo_log info "扩展 ext 文件系统：$part_dev"
      run "resize2fs $part_dev"
      ;;
    xfs)
      # xfs_growfs 需要挂载点
      local mnt
      mnt=$(findmnt -no TARGET "$part_dev" || true)
      if [[ -z "$mnt" ]]; then
        # 如果是根分区，默认 /
        if [[ "$(findmnt -no SOURCE /)" == "$part_dev" ]]; then
          mnt="/"
        else
          echo_log error "XFS 需在线扩容且必须挂载：请确认 $part_dev 的挂载点。"
          exit 1
        fi
      fi
      echo_log info "扩展 XFS 文件系统：设备=$part_dev 挂载点=$mnt"
      run "xfs_growfs $mnt"
      ;;
    btrfs)
      # 常见于子卷，在线扩容需要设备背后的块扩容，本脚本不深入处理复杂btrfs拓扑
      echo_log warn "检测到 btrfs，请手动确认子卷/设备布局后再扩容。"
      exit 1
      ;;
    *)
      echo_log warn "未适配的文件系统类型：$fs_type，请手动处理。"
      exit 1
      ;;
  esac
}

expand_lvm_single_pv() {
  local lv_path="$1"

  local vg lv
  vg=$(lvs --noheadings -o vg_name "$lv_path" | awk '{$1=$1;print}')
  lv=$(lvs --noheadings -o lv_path "$lv_path" | awk '{$1=$1;print}')
  if [[ -z "$vg" || -z "$lv" ]]; then
    echo_log error "无法解析 LVM 信息：$lv_path"
    exit 1
  fi

  # 找到该VG的PV列表
  mapfile -t pv_list < <(pvs --noheadings -o pv_name,vg_name | awk -v v="$vg" '$2==v {print $1}')
  if [[ "${#pv_list[@]}" -ne 1 ]]; then
    echo_log warn "当前VG含有${#pv_list[@]}个PV，出于风控，本脚本仅支持单PV自动扩容。请手动处理。"
    exit 1
  fi
  local pv_dev="${pv_list[0]}"

  read -r disk pnum < <(split_disk_part "$pv_dev")
  if [[ -z "$disk" || -z "$pnum" ]]; then
    echo_log error "无法解析PV底层磁盘与分区号：$pv_dev"
    exit 1
  fi

  echo_log info "扩展 PV 后端分区：磁盘=$disk 分区号=$pnum"
  if ! command -v growpart >/dev/null 2>&1; then
    echo_log error "缺少 growpart，无法在线扩分区。"
    exit 1
  fi
  run "growpart $disk $pnum"
  run "partprobe $disk || true"
  run "udevadm settle || true"
  sleep 2

  echo_log info "pvresize $pv_dev"
  run "pvresize $pv_dev"

  echo_log info "lvextend -r 将空闲空间全部扩至 $lv"
  run "lvextend -r -l +100%FREE \"$lv\""
}

main() {
  require_root
  check_lock
  trap release_lock EXIT
  ensure_tools

  # 识别根分区 source（如 /dev/vda1 或 /dev/mapper/vg-root）
  local root_src
  root_src=$(findmnt -no SOURCE /)
  if [[ -z "$root_src" && -z "$TARGET_PART" ]]; then
    echo_log error "无法识别根分区。请使用 --device 指定分区设备。"
    exit 1
  fi

  local target="${TARGET_PART:-$root_src}"
  echo_log info "目标扩容对象：$target"

  if is_lvm_lv "$target"; then
    echo_log info "检测到 LVM 根卷，执行单PV LVM 扩容流程。"
    expand_lvm_single_pv "$target"
  else
    echo_log info "检测到裸分区根卷，执行分区+文件系统扩容流程。"
    expand_plain_partition "$target"
  fi

  echo_log success "磁盘扩容完成。当前磁盘与挂载情况："
  lsblk -f
  echo
  df -hT
}

main "$@"
