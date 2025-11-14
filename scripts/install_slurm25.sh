#!/bin/bash
set -e

# 本地包目录
DEB_DIR="/mnt/hgfs/D/VMs/Slurm-Clusters-Debian/packages"

echo "=============================="
echo "1️⃣ 卸载旧版本 Slurm"
sudo systemctl stop slurmd slurmctld slurmdbd || true
sudo apt remove --purge -y \
    slurm-wlm-basic-plugins \
    slurm-wlm-mysql-plugin \
    slurmd \
    slurmctld \
    slurmdbd \
    slurm-smd \
    slurm-smd-slurmd \
    slurm-client \
    slurm-wlm || true
sudo apt autoremove -y
sudo rm -rf /etc/slurm

echo "=============================="
echo "2️⃣ 安装 dpkg-dev（生成本地仓库索引）"
sudo apt update
sudo apt install -y dpkg-dev

echo "=============================="
echo "3️⃣ 建立本地仓库"
cd "$DEB_DIR"
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
echo "deb [trusted=yes] file:$DEB_DIR ./" | sudo tee /etc/apt/sources.list.d/slurm-local.list
sudo apt update

echo "=============================="
echo "4️⃣ 安装 Munge（如果未安装）"
sudo apt install -y munge libmunge2
sudo systemctl enable --now munge
sudo apt install -y libpmix-dev libpmix2

echo "=============================="
echo "5️⃣ 安装 Slurm 25.11.0 核心包及依赖"
# 列出本地包顺序安装，确保依赖正确
sudo apt install -y \
    "$DEB_DIR"/libhttp-parser2.9_*.deb \
    "$DEB_DIR"/libmariadb3_*.deb \
    "$DEB_DIR"/librdkafka1_*.deb \
    "$DEB_DIR"/slurm-smd_*.deb \
    "$DEB_DIR"/slurm-smd-slurmd_*.deb 

echo "=============================="
echo "6️⃣ 启动 Slurm 服务"
#sudo systemctl enable --now slurmctld
sudo systemctl enable --now slurmd
#sudo systemctl enable --now slurmdbd

echo "=============================="
echo "7️⃣ 检查状态"
systemctl status munge --no-pager
#systemctl status slurmctld --no-pager
systemctl status slurmd --no-pager
#systemctl status slurmdbd --no-pager

echo "=============================="
echo "8️⃣ Slurm 25.11.0 离线安装完成"
echo "请确认 slurm.conf 已正确配置，并在所有节点启动 slurmd"


