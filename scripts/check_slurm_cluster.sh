#!/bin/bash
# slurm_cluster_health_check.sh
# 兼容旧 Slurm，没有 --expand

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${YELLOW}===== Slurm 控制守护进程检查 =====${RESET}"
systemctl is-active --quiet slurmctld && echo -e "slurmctld: ${GREEN}ACTIVE${RESET}" || echo -e "slurmctld: ${RED}INACTIVE${RESET}"
systemctl is-active --quiet slurmdbd && echo -e "slurmdbd: ${GREEN}ACTIVE${RESET}" || echo -e "slurmdbd: ${RED}INACTIVE${RESET}"

echo -e "${YELLOW}\n===== 节点状态检查 (sinfo) =====${RESET}"
sinfo -N -o "%N %t %c %m"

# 展开节点列表
nodes=$(sinfo -h -o "%N" | sed 's/\[/ /g;s/\]/ /g' | awk -F'[- ,]' '{ 
  if (NF==1) { print $1 } 
  else { 
    for(i=$2;i<=$3;i++) printf "%s%02d\n",$1,i 
  } 
}')

echo -e "${YELLOW}\n===== 每个节点 slurmd 守护进程状态 =====${RESET}"
for node in $nodes; do
    status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 $node "systemctl is-active slurmd" 2>/dev/null)
    if [[ $status == "active" ]]; then
        echo -e "$node: ${GREEN}ACTIVE${RESET}"
    else
        echo -e "$node: ${RED}INACTIVE${RESET}"
    fi
done

echo -e "${YELLOW}\n===== 每个节点时间同步检查 (chrony) =====${RESET}"
for node in $nodes; do
    echo -e "${YELLOW}Node: $node${RESET}"
    ssh -o BatchMode=yes -o ConnectTimeout=5 $node "chronyc tracking; chronyc sources -v" 2>/dev/null || echo -e "$node: ${RED}chrony check failed${RESET}"
done

echo -e "${YELLOW}\n===== 简单作业调度测试 =====${RESET}"
JOB_FILE=$(mktemp /tmp/slurm_test.XXXX.sh)
cat << 'EOF' > $JOB_FILE
#!/bin/bash
#SBATCH --job-name=test_slurm_check
#SBATCH --output=/tmp/test_slurm_check.out
#SBATCH --time=00:01:00
#SBATCH --partition=debug

echo "Hello from $(hostname) at $(date)"
sleep 10
EOF

JOBID=$(sbatch $JOB_FILE | awk '{print $4}')
echo -e "Submitted test job: $JOBID"
squeue -j $JOBID
echo -e "Job will run for ~10 seconds, output in /tmp/test_slurm_check.out"

rm -f $JOB_FILE

echo -e "${YELLOW}\n===== 检查完成 =====${RESET}"
