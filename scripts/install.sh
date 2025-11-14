#!/bin/bash
# =========================================================
# install.sh v4 - Ubuntu 22.04 系统与 Slurm 集群离线安装脚本
# Author: Guo Zhibin
# 功能: 自动化部署 Ubuntu 22.04 + Slurm 集群环境
# =========================================================
# /mnt/hgfs/D/GenAI/Presales/projects/中国科学院香港创新研究院人工智能与机器人创新中心(CAIR)/slurm-cluster



check_hosts_status() {
        

    log_info "安装前检查相关主机网络连通性"
    for ip in "${IPS_ARRAY[@]}" "$CONTROLLER_IP"; do
        ping -c 2 "$ip" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            log_error "无法连接到主机 $ip，请检查网络设置。" 
            exit 1
        fi
    done 
    log_success "所有相关主机均可连通。"


    # 检查 SSH 免密登录
    log_info "检查 SSH 免密登录状态..."
    for ip in "${IPS_ARRAY[@]}" "$CONTROLLER_IP"; do
        ssh -o BatchMode=yes -o ConnectTimeout=5 "${USER_NAME}@${ip}" "exit"  > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            log_error "无法通过 SSH 连接到主机 $ip，请确保已设置免密登录。"
            log_info "正在尝试建立 SSH 免密登录..."
            create_host_trust
            # 再次测试连接
            ssh -o BatchMode=yes -o ConnectTimeout=5 "${USER_NAME}@${ip}" "exit"  > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                log_error "仍然无法通过 SSH 连接到主机 $ip，请手动检查 SSH 设置。"
                exit 1
            fi
        else
            log_success "已通过 SSH 连接到主机 $ip。"
        fi
    done


    # 检查所有主机操作系统是否满足要求： Ubuntu 22.04 | Debian 12
    log_info "检查所有主机操作系统版本..."
    for ip in "${IPS_ARRAY[@]}" "$CONTROLLER_IP"; do
        OS_INFO=$(ssh "${USER_NAME}@${ip}" "source /etc/os-release && echo \$NAME \$VERSION_ID")
        if [[ "$OS_INFO" != *"Ubuntu 22.04"* && "$OS_INFO" != *"Debian 12"* ]]; then
            log_error "主机 $ip 的操作系统版本不符合要求: $OS_INFO"
            exit 1
        else
            log_success "主机 $ip 的操作系统版本符合要求: $OS_INFO"
        fi
    done


}

create_host_trust() {
    # ---------------------------------------------------------
    # 在当前主机上操作，建立该主机到其他所有主机的信任
    # ---------------------------------------------------------
    # 检查 sshpass 工具
    if ! command -v sshpass &>/dev/null; then
        echo "🧩 未检测到 sshpass，正在安装..."
        sudo apt update -y >/dev/null 2>&1
        sudo apt install -y sshpass >/dev/null 2>&1
    fi

    # 输入远程主机用户和密码（统一密码） 
    echo -n "请输入远程主机 $USER_NAME 的密码（所有节点相同）: "
    read -s PASSWORD
    echo ""
    echo "--------------------------------------------------------------"

    # 1️⃣ 生成 SSH 密钥（如果不存在）
    if [ ! -f ~/.ssh/id_rsa ]; then
        echo "🔑 未检测到 SSH 密钥，正在生成..."
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
    else
        echo "✅ SSH 密钥已存在，跳过生成。"
    fi 


    # 2️⃣ 向所有节点分发公钥（包括控制节点）
    for ip in "${IPS_ARRAY[@]}" "$CONTROLLER_IP"; do
        echo "--------------------------------------------------------------"
        echo "📤 正在分发公钥到主机: $ip"
        # 跳过 known_hosts 确认
        ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts 2>/dev/null
        # 使用 sshpass 自动执行 ssh-copy-id
        echo "sshpass -p ****** ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub ${USER_NAME}@${ip}"
        # 让 ssh-copy-id 的错误信息显示到控制台（不要重定向 stderr）
        sshpass -p "$PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub ${USER_NAME}@"${ip}"
        if [ $? -eq 0 ]; then
            echo "✅ 已成功建立信任: $ip"
        else
            echo "❌ 建立信任失败: $ip"
        fi
    done

}

config_offline_apt_repo() {
    # 配置离线APT源
    log_info "配置当前主机离线APT源..."
    if [ -d "$LOCAL_REPO_PATH" ]; then
        if [ -f /etc/apt/sources.list ]; then
            sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d_%H%M%S)
        fi 
        echo "deb [trusted=yes] file:$LOCAL_REPO_PATH ./" | sudo tee /etc/apt/sources.list.d/slurm-local.list > /dev/null 2>&1
        sudo apt update > /dev/null 2>&1
    fi

    # 将离线源部署到所有远程主机中并在远程主机上配置离线APT源
    log_info "将离线APT源部署到所有远程主机..."
    for ip in "${IPS_ARRAY[@]}"; do
        log_info "正在配置主机 $ip 的离线APT源..."
        # 复制本地仓库到远程主机
        ssh "${USER_NAME}@${ip}" "mkdir -p $REMOTE_REPO_PATH"  > /dev/null 2>&1
        rsync -avz --delete "$LOCAL_REPO_PATH/" "${USER_NAME}@${ip}:$REMOTE_REPO_PATH/" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_success "主机 $ip 的离线APT源文件同步完成。"
        else
            log_error "主机 $ip 的离线APT源文件同步失败。"
            exit 1 
        fi
        ssh "${USER_NAME}@${ip}" " 
            if [ -f /etc/apt/sources.list ]; then
                sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d_%H%M%S)
            fi
            echo "deb [trusted=yes] file:$REMOTE_REPO_PATH ./" | sudo tee /etc/apt/sources.list.d/slurm-local.list > /dev/null 2>&1
            sudo apt update > /dev/null 2>&1
        "  > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_success "主机 $ip 的离线APT源配置完成。"
        else
            log_error "主机 $ip 的离线APT源配置失败。"
            exit 1 
        fi
    done

}


all_hosts_operation() { 
    # 根据每个主机的 IP 和对应节点名称修改主机名称为节点名称
    local SET_HOSTNAME_CMD="sudo hostnamectl set-hostname ${CONTROLLER_HOSTNAME}"
    ssh "${USER_NAME}@${CONTROLLER_IP}" "${SET_HOSTNAME_CMD}"  > /dev/null 2>&1

    for i in "${!HOSTNAMES_ARRAY[@]}"; do
        local SET_HOSTNAME_CMD="sudo hostnamectl set-hostname ${HOSTNAMES_ARRAY[$i]}" 
        ssh "${USER_NAME}@${IPS_ARRAY[$i]}" "${SET_HOSTNAME_CMD}" > /dev/null 2>&1
    done

    # 对于每个节点主机, 从控制节点同步 /etc/hosts 文件
    for ip in "${IPS_ARRAY[@]}"; do
        log_info "正在将控制节点的 /etc/hosts 文件同步到主机 $ip ..."
        scp "${USER_NAME}@${CONTROLLER_IP}:/etc/hosts" "${USER_NAME}@${ip}:/tmp/hosts" > /dev/null 2>&1
        ssh "${USER_NAME}@${ip}" "sudo mv /tmp/hosts /etc/hosts" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_success "主机 $ip 的 /etc/hosts 文件同步完成。"
        else
            log_error "主机 $ip 的 /etc/hosts 文件同步失败。"
            exit 1
        fi
    done 

    for ip in "$CONTROLLER_IP" "${IPS_ARRAY[@]}" ; do
        
        # 在所有主机节点上创建用户和用户组
        log_info "正在主机 $ip 上创建用户和用户组..."
        ssh "${USER_NAME}@${ip}" "
            # 创建 munge 用户和组
            if ! id -u munge &>/dev/null; then
                sudo groupadd -g $MUNGEUSER munge
                sudo useradd -m -u $MUNGEUSER -g munge -s /bin/bash munge
            fi
            # 创建 slurm 用户和组
            if ! id -u slurm &>/dev/null; then
                sudo groupadd -g $SLURMUSER slurm
                sudo useradd -m -u $SLURMUSER -g slurm -s /bin/bash slurm
            fi
        " > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_success "主机 $ip 上用户和用户组创建完成。"
        else
            log_error "主机 $ip 上用户和用户组创建失败。"
            exit 1
        fi


        log_info "正在主机 $ip 上安装munge组件..."
        ssh "${USER_NAME}@${ip}" "
            sudo apt install munge -y
            sudo systemctl enable --now munge
            systemctl status munge
        "  > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_success "主机 $ip 上munge组件安装完成。"
        else
            log_error "主机 $ip 上munge组件安装失败。"
            exit 1
        fi

        # 同步master节点的munge key到各个节点
        if [ "$ip" != "$CONTROLLER_IP" ]; then
            log_info "正在将控制节点的 /etc/munge/munge.key 文件同步到主机 $ip ..."
            scp "${USER_NAME}@${CONTROLLER_IP}:/etc/munge/munge.key" "${USER_NAME}@${ip}:/tmp/munge.key" > /dev/null 2>&1
            ssh "${USER_NAME}@${ip}" "
                sudo mv /tmp/munge.key /etc/munge/munge.key
                sudo chown munge:munge /etc/munge/munge.key
                sudo chmod 400 /etc/munge/munge.key
                sudo systemctl restart munge
            " > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                log_success "主机 $ip 上的 munge.key 文件同步完成。"
            else
                log_error "主机 $ip 上的 munge.key 文件同步失败。"
                exit 1
            fi
        fi

    done

    
}



all_hosts_operation_bak() {
    # 在所有远程主机上执行指定命令
    # 用法: all_hosts_operation "<command>"
    # 如果未传入参数，则回退到全局变量 $COMMAND（保持向后兼容）
    local COMMAND_TO_RUN="${1:-$COMMAND}"
    for ip in "${IPS_ARRAY[@]}" "$CONTROLLER_IP"; do
        log_info "正在主机 $ip 上执行命令: $COMMAND_TO_RUN"
        ssh "${USER_NAME}@${ip}" "$COMMAND_TO_RUN"  > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_success "主机 $ip 上命令执行成功。"
        else
            log_error "主机 $ip 上命令执行失败。"
            exit 1
        fi
    done
}



START_TIME=$(date +%s)
LOG_FILE="/var/log/slurm-install-$(date +%Y%m%d_%H%M%S).log"
REMOTE_REPO_PATH="/tmp/slurm-offline-repo"

# ---------- 颜色 ----------
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; BLUE="\e[34m"; RESET="\e[0m"

log_info()    { echo -e "${BLUE}[*]${RESET} $1"; echo "[*] $1" >> "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✔]${RESET} $1"; echo "[✔] $1" >> "$LOG_FILE"; }
log_warn()    { echo -e "${YELLOW}[!]${RESET} $1"; echo "[!] $1" >> "$LOG_FILE"; }
log_error()   { echo -e "${RED}[✘]${RESET} $1"; echo "[✘] $1" >> "$LOG_FILE"; }

# log_success "创建输出目录：${OUTPUT_DIR}"


MUNGEUSER=2001
SLURMUSER=2002

# 从控制台询问用户输入
# read -p "请输入本地软件包仓库路径: " LOCAL_REPO_PATH
# read -p "请输入集群节点主机名（逗号分隔）: " NODE_HOSTNAMES
# read -p "请输入集群节点 IP 地址（逗号分隔）: " NODE_IPS
# read -p "请输入 Slurm 控制节点主机名: " CONTROLLER_HOSTNAME
# read -p "请输入 Slurm 控制节点 IP 地址: " CONTROLLER_IP 
# read -p "请输入远程主机的用户名（所有节点相同）: " USER_NAME
echo ""
# 先定义默认值以便测试
USER_NAME="${USER_NAME:-ubuntu}"
LOCAL_REPO_PATH="/home/ubuntu/slurm-25.11.0-packages-offline"
NODE_HOSTNAMES="node01,node02"
NODE_IPS="192.168.100.129,192.168.100.130"
CONTROLLER_HOSTNAME="master"
CONTROLLER_IP="192.168.100.128"



# 根据用户输入生成节点列表和hosts文件内容
IFS=',' read -r -a HOSTNAMES_ARRAY <<< "$NODE_HOSTNAMES"
IFS=',' read -r -a IPS_ARRAY <<< "$NODE_IPS"
# 根据IPS_ARRAY和HOSTNAMES_ARRAY的索引一一对应关系





# check_hosts_status
config_offline_apt_repo
all_hosts_operation


# # 生成 Slurm 节点列表
# NODES=""
# for i in "${!HOSTNAMES_ARRAY[@]}"; do
#     echo "Processing node: ${HOSTNAMES_ARRAY[$i]}"
#     NODES+="${HOSTNAMES_ARRAY[$i]} slots=4, State=UNKNOWN"$'\n'
# done
# NODES=${NODES%$'\n'}  # 去掉最后的换行符
# printf '%s\n' "$NODES"


# HOSTS_CONTENT="${CONTROLLER_IP} ${CONTROLLER_HOSTNAME}"$'\n'
# for i in "${!HOSTNAMES_ARRAY[@]}"; do
#     HOSTS_CONTENT+="${IPS_ARRAY[$i]} ${HOSTNAMES_ARRAY[$i]}"$'\n'
# done
# HOSTS_CONTENT=${HOSTS_CONTENT%$'\n'}  # 去掉最后的换行符

# # 将hosts内容写入/etc/hosts文件, 写入前备份原文件
# sudo cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)
# echo -e "$HOSTS_CONTENT" | sudo tee /etc/hosts



echo "===== $(date) 开始安装 =====" >> "$LOG_FILE"

