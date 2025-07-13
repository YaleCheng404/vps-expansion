#!/bin/bash
# Description: 磁盘分区与扩容工具
# Usage: bash expansion.sh

LOCKfile="/root/.$(basename "$0").lock"
LOGfile="/root/.$(basename "$0").log"

echo_log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    case $level in
        success) color="\033[1;32m" ;;
        error)   color="\033[1;31m" ;;
        warn)    color="\033[1;33m" ;;
        info)    color="\033[1;34m" ;;
        *)       color="\033[1;37m" ;;
    esac

    echo -e "${color}${message}\033[0m"
    echo "${timestamp}: ${message}" >> "$LOGfile"
}

check_lock() {
    if [ -f "$LOCKfile" ]; then
        echo_log error "操作已在进行中，请勿重复运行。若需强制运行，请删除文件: $LOCKfile"
        exit 1
    fi
    touch "$LOCKfile"
}

release_lock() {
    rm -f "$LOCKfile"
}

manage_services() {
    local action=$1
    local services=(
        "httpd" "nginxd" "mysqld" "pureftpd" "wdcp" "wdapache" 
        "redis_6379" "memcached" "bt" "nginx" "redis" "tomcat" 
        "tomcat7" "php-fpm-52" "php-fpm-53" "php-fpm-54" "php-fpm-55"
        "php-fpm-56" "php-fpm-70" "php-fpm-71" "php-fpm-72"
        "php-fpm-73" "php-fpm-74" "php-fpm-80"
    )
    
    for service in "${services[@]}"; do
        if [ -f "/etc/init.d/$service" ]; then
            echo_log info "执行: service $service $action"
            service "$service" "$action"
        fi
    done
}

expand_disk() {
    # 获取可用磁盘列表
    local devices=()
    while IFS= read -r dev; do
        [ -n "$dev" ] && devices+=("$dev")
    done < <(ls /dev/vd[b-z] 2>/dev/null)
    
    if [ ${#devices[@]} -eq 0 ]; then
        echo_log error "未找到可用磁盘设备 (/dev/vd[b-z])"
        return 1
    fi

    # 显示设备列表
    echo_log info "可用磁盘设备:"
    printf '  %s\n' "${devices[@]}"
    
    # 选择设备
    local selected_dev=""
    read -rp "请输入设备名 (默认: ${devices[0]}): " selected_dev
    selected_dev="${selected_dev:-${devices[0]}}"
    
    while [[ ! -e "$selected_dev" ]]; do
        echo_log warn "无效设备名，请重新输入"
        read -rp ":" selected_dev
    done

    # 准备扩容
    local mount_point swap_status swap_path
    mount_point=$(df -vh | awk -v dev="${selected_dev}1" '$1 == dev {print $6}')
    swap_status=$(free -m | awk '/Swap:/{print $2}')
    swap_path=$(awk '/swap/{print $1}' /etc/fstab)

    [ "$swap_status" -ne 0 ] && swapoff "$swap_path"
    [ -d "/www/server/panel" ] && manage_services stop

    # 安装必要工具
    if ! command -v fuser &>/dev/null; then
        echo_log info "正在安装必要工具: psmisc"
        yum -y install psmisc || {
            echo_log error "工具安装失败"
            return 1
        }
    fi

    # 卸载分区
    echo_log info "卸载分区: $mount_point"
    fuser -km "$mount_point"
    sleep 2
    if ! umount "$mount_point"; then
        echo_log error "分区卸载失败"
        return 1
    fi

    # 调整分区
    echo_log info "开始磁盘扩容 (耗时可能较长)..."
    local start_sector
    start_sector=$(parted -s "$selected_dev" unit s print | awk '/primary/{print $2}' | tr -d 's')

    if ! parted -s "$selected_dev" rm 1 && \
       parted -s "$selected_dev" mkpart primary "${start_sector}s" 100%; then
        echo_log error "分区调整失败"
        return 1
    fi

    # 调整文件系统
    if ! resize2fs -f "${selected_dev}1"; then
        echo_log error "文件系统调整失败"
        return 1
    fi

    # 恢复环境
    mount -a
    [ "$swap_status" -ne 0 ] && swapon "$swap_path"
    [ -d "/www/server/panel" ] && manage_services start

    # 显示结果
    echo_log success "磁盘扩容成功"
    df -vh
}

# 主流程
check_lock
trap release_lock EXIT

expand_disk || {
    echo_log error "扩容过程出错，正在恢复服务..."
    [ -d "/www/server/panel" ] && manage_services start
    release_lock
    exit 1
}
