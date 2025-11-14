#!/bin/bash
# =========================================================
# collect_sysinfo.sh v4 - Ubuntu 22.04 系统与 Slurm 集群信息收集
# Author: linux guo
# 功能: 系统巡检、故障排查、Slurm 集群状态汇总与节点健康报警
# =========================================================

START_TIME=$(date +%s)
OUTPUT_DIR="/tmp/sysinfo_$(hostname)_$(date +%Y%m%d_%H%M%S)"
ARCHIVE_FILE="${OUTPUT_DIR}.tar.gz"
LOG_FILE="/var/log/sysinfo_collect.log"
mkdir -p "$OUTPUT_DIR"

# ---------- 颜色 ----------
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; BLUE="\e[34m"; RESET="\e[0m"

log_info()    { echo -e "${BLUE}[*]${RESET} $1"; echo "[*] $1" >> "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✔]${RESET} $1"; echo "[✔] $1" >> "$LOG_FILE"; }
log_warn()    { echo -e "${YELLOW}[!]${RESET} $1"; echo "[!] $1" >> "$LOG_FILE"; }
log_error()   { echo -e "${RED}[✘]${RESET} $1"; echo "[✘] $1" >> "$LOG_FILE"; }

log_success "创建输出目录：${OUTPUT_DIR}"
echo "===== $(date) 开始收集 =====" >> "$LOG_FILE"

# ---------- 模块函数 ----------
collect_basic_info() {
    log_info "收集系统基本信息..."
    {
        echo "===== OS 信息 ====="
        lsb_release -a 2>/dev/null || cat /etc/os-release
        echo; echo "===== 内核与启动 ====="; uname -a; uptime -p
        echo; echo "===== CPU 与内存 ====="; lscpu; free -h
        echo; echo "===== 磁盘与挂载 ====="; lsblk; df -hT
    } > "${OUTPUT_DIR}/system_basic.txt"
    log_success "系统信息已收集。"
}

collect_hardware_info() {
    log_info "收集硬件信息..."
    {
        echo "===== PCI 设备 ====="; lspci
        echo; echo "===== USB 设备 ====="; lsusb
        echo; echo "===== 磁盘详细信息 ====="; sudo fdisk -l 2>/dev/null
    } > "${OUTPUT_DIR}/hardware_info.txt"
    log_success "硬件信息已收集。"
}

collect_network_info() {
    log_info "收集网络信息..."
    {
        echo "===== IP 与路由 ====="; ip addr show; echo; ip route show
        echo; echo "===== DNS 配置 ====="; cat /etc/resolv.conf
        echo; echo "===== 主机名与 hosts ====="; hostnamectl; cat /etc/hosts
    } > "${OUTPUT_DIR}/network_info.txt"
    log_success "网络信息已收集。"
}

collect_user_info() {
    log_info "收集用户与权限信息..."
    {
        echo "===== 当前登录用户 ====="; who
        echo; echo "===== 系统用户 ====="; cat /etc/passwd
        echo; echo "===== sudo 用户 ====="; grep '^sudo' /etc/group
    } > "${OUTPUT_DIR}/user_info.txt"
    log_success "用户与权限信息已收集。"
}

collect_software_info() {
    log_info "收集软件与服务信息..."
    {
        echo "===== 已安装软件包数 ====="; dpkg -l | wc -l
        echo; echo "===== 最近安装的软件 ====="; grep " install " /var/log/dpkg.log* 2>/dev/null | tail -20
        echo; echo "===== 运行中服务 ====="; systemctl list-units --type=service --state=running
        echo; echo "===== Docker 信息 ====="; docker ps -a 2>/dev/null
    } > "${OUTPUT_DIR}/software_info.txt"
    log_success "软件与服务信息已收集。"
}

collect_config_files() {
    log_info "复制关键配置文件..."
    mkdir -p "${OUTPUT_DIR}/configs"
    cp /etc/hosts /etc/fstab /etc/ssh/sshd_config /etc/nsswitch.conf 2>/dev/null -t "${OUTPUT_DIR}/configs/"
    cp /etc/systemd/journald.conf /etc/security/limits.conf 2>/dev/null -t "${OUTPUT_DIR}/configs/"
    log_success "系统配置文件已复制。"
}

collect_slurm_info() {
    log_info "检查 Slurm 安装状态..."
    if command -v sinfo >/dev/null 2>&1; then
        log_success "检测到 Slurm，开始收集 Slurm 信息..."
        SLURM_DIR="${OUTPUT_DIR}/slurm"
        mkdir -p "$SLURM_DIR"

        # 基本状态
        {
            echo "===== Slurm 版本 ====="; scontrol version
            echo; echo "===== 队列信息 ====="; squeue -a
            echo; echo "===== 用户作业历史（最近20条） ====="; sacct -o jobid,user,partition,state,start,end | tail -20 2>/dev/null
        } > "$SLURM_DIR/slurm_status.txt"

        # 复制配置文件
        [ -d /etc/slurm ] && cp -a /etc/slurm/*.conf "$SLURM_DIR/" 2>/dev/null
        [ -f /etc/munge/munge.key ] && cp -a /etc/munge/munge.key "$SLURM_DIR/" 2>/dev/null

        # Slurm 日志
        mkdir -p "$SLURM_DIR/logs"
        cp /var/log/slurm* "$SLURM_DIR/logs/" 2>/dev/null
        journalctl -u slurmctld -n 200 > "$SLURM_DIR/logs/slurmctld_journal.txt" 2>/dev/null

        # ---------- 节点健康报告与自动报警 ----------
        log_info "生成 Slurm 节点健康检测报告..."
        NODES_HEALTH_FILE="$SLURM_DIR/slurm_nodes_health.txt"
        echo -e "节点名\t状态" > "$NODES_HEALTH_FILE"

        DOWN_NODES=0
        DRAIN_NODES=0

        while read -r node state; do
            echo -e "$node\t$state" >> "$NODES_HEALTH_FILE"
            if [[ "$state" == "down" ]]; then ((DOWN_NODES++)); fi
            if [[ "$state" == "drain" ]]; then ((DRAIN_NODES++)); fi
        done < <(sinfo -h -o "%N %T")

        echo -e "\nSummary:" >> "$NODES_HEALTH_FILE"
        for st in idle alloc drain down unknown; do
            COUNT=$(grep -cw "$st" "$NODES_HEALTH_FILE")
            echo "$st: $COUNT" >> "$NODES_HEALTH_FILE"
        done

        # 控制台报警输出
        log_info "节点状态检查结果（异常节点红色高亮）："
        while read -r node state; do
            if [[ "$state" == "down" ]]; then
                echo -e "${RED}$node  DOWN${RESET}"
            elif [[ "$state" == "drain" ]]; then
                echo -e "${RED}$node  DRAIN${RESET}"
            else
                echo -e "$node  $state"
            fi
        done < <(grep -v "^节点名" "$NODES_HEALTH_FILE")

        if (( DOWN_NODES + DRAIN_NODES > 0 )); then
            log_warn "发现异常节点：down=$DOWN_NODES, drain=$DRAIN_NODES"
        else
            log_success "所有节点状态正常。"
        fi

        log_success "Slurm 节点健康报告已生成：$NODES_HEALTH_FILE"
    else
        log_warn "未检测到 Slurm，跳过 Slurm 信息收集。"
    fi
}

collect_logs() {
    log_info "收集系统日志（最后1000行）..."
    {
        journalctl -p err -n 1000
        dmesg | tail -n 1000
        uptime
        who -a
        last -n 20
    } > "${OUTPUT_DIR}/logs.txt"
    log_success "系统日志已收集。"
}

collect_ldap_info() {
    log_info "收集 LDAP 服务及配置状态..."

    LDAP_DIR="${OUTPUT_DIR}/ldap"
    mkdir -p "$LDAP_DIR"

    # 复制主要配置文件
    for file in /etc/ldap/ldap.conf /etc/sssd/sssd.conf; do
        [ -f "$file" ] && cp -a "$file" "$LDAP_DIR/" 2>/dev/null
    done

    # 检查客户端工具
    {
        echo "===== LDAP 客户端工具 ====="
        which ldapsearch 2>/dev/null || echo "ldapsearch 未安装"
        which sssd 2>/dev/null || echo "sssd 未安装"
        which nslcd 2>/dev/null || echo "nslcd 未安装"
    } > "$LDAP_DIR/ldap_tools.txt"

    # 检查服务状态
    {
        echo "===== SSSD / nslcd 服务状态 ====="
        systemctl status sssd nslcd 2>/dev/null | head -n 20
    } > "$LDAP_DIR/ldap_service_status.txt"

    # LDAP 连接测试（仅在 ldapsearch 可用时）
    if command -v ldapsearch >/dev/null 2>&1; then
        echo "===== LDAP 测试查询 =====" > "$LDAP_DIR/ldap_test.txt"
        ldapsearch -x -LLL -H ldap://localhost -b "" -s base "(objectclass=*)" 2>/dev/null >> "$LDAP_DIR/ldap_test.txt"
    else
        echo "ldapsearch 未安装，无法测试 LDAP 查询" > "$LDAP_DIR/ldap_test.txt"
    fi

    # LDAP 用户与组信息
    {
        echo "===== LDAP 用户列表 ====="
        getent passwd | grep -v '^#' | grep -E '^[^:]+:[^:]*:[0-9]+:[0-9]+:.*:.*:.*$'
        echo; echo "===== LDAP 组列表 ====="
        getent group | grep -v '^#'
    } > "$LDAP_DIR/ldap_users_groups.txt"

    log_success "LDAP 信息已收集，输出目录：$LDAP_DIR"
}


# ---------- 主执行 ----------
collect_basic_info
collect_hardware_info
collect_network_info
collect_user_info
collect_software_info
collect_config_files
collect_slurm_info
collect_ldap_info
collect_logs

# ---------- 打包 ----------
log_info "打包所有收集结果..."
tar -czf "$ARCHIVE_FILE" -C "$(dirname "$OUTPUT_DIR")" "$(basename "$OUTPUT_DIR")"
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_success "信息收集完成 ✅"
log_success "输出文件：${ARCHIVE_FILE}"
log_success "总耗时：${DURATION} 秒"
echo "===== $(date) 结束，总耗时 ${DURATION} 秒 =====" >> "$LOG_FILE"


