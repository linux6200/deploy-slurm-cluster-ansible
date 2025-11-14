# Ansible Slurm Cluster Deployment (v2)

本项目使用 **Ansible** 自动化部署 **Slurm 集群**（Ubuntu 22.04 + Slurm apt 包），支持动态生成 `slurm.conf`，自动分发 Munge key 和设置 MariaDB / slurmdbd。

---

## 目录结构

```
slurm-ansible-v2/
├── ansible.cfg
├── inventory/
│   └── hosts.ini           # 控制节点与计算节点信息
├── group_vars/
│   └── all.yml             # 全局变量（Slurm/MariaDB/Munge）
├── site.yml                # 主 playbook
└── roles/
    ├── common/
    │   └── tasks/main.yml  # 基础环境安装
    ├── munge/
    │   └── tasks/main.yml  # Munge 安装与密钥生成
    ├── mariadb/
    │   ├── tasks/main.yml  # MariaDB 安装与用户/数据库创建
    │   └── handlers/main.yml
    ├── slurm-controller/
    │   ├── tasks/main.yml
    │   ├── templates/slurm.conf.j2
    │   ├── templates/slurmdbd.conf.j2
    │   └── handlers/main.yml
    └── slurm-compute/
        └── tasks/main.yml  # Slurm compute 节点安装
```

---

## 主要功能

1. 自动安装基础环境（Python3、build-essential、chrony 等）。
2. 自动安装 Munge 并生成密钥，分发到所有节点。
3. 安装 MariaDB 并创建 SlurmDB 数据库和用户。
4. 安装 Slurm Controller 和 SlurmDBD。
5. 动态生成 slurm.conf：
   - 自动读取 compute 节点 CPU 核数和内存容量。
   - 自动填充 NodeName、NodeAddr、CPUs、RealMemory。
6. 安装 Slurm Compute 节点（slurmd）。
7. 默认分区：debug。

---

## 部署步骤

1. 解压项目：

```bash
unzip slurm-ansible-v2.zip -d slurm-ansible-v2
cd slurm-ansible-v2
```

2. （可选）使用 Ansible Vault 加密敏感密码：

```bash
ansible-vault encrypt_string 'root真实密码' --name 'mariadb_root_password' >> group_vars/all.yml
ansible-vault encrypt_string 'slurmdbd真实密码' --name 'slurmdbd_password' >> group_vars/all.yml
```

3. 运行 Playbook：

```bash
ansible-playbook -i inventory/hosts.ini site.yml --ask-become-pass
```

> `--ask-become-pass` 是因为 Playbook 需要 sudo 权限安装软件和配置服务。

4. 调试模式运行 Playbook：
```
ansible-playbook -i inventory/hosts.ini site.yml --limit controller -vvv
```

---

## 验证集群状态

1. 登录 controller 节点：

```bash
sinfo -Nl
scontrol show nodes
sacctmgr show cluster
```

2. 查看 Munge、slurmd、slurmctld、slurmdbd 服务状态：

```bash
systemctl status munge slurmd slurmctld slurmdbd
```

---

## 注意事项

- 默认分区名称为 debug。
- 默认 MariaDB root 密码为 root123，slurmdbd 密码为 slurmdb123。请在生产环境中修改或加密。
- 当前 Slurm 通过 apt 安装，版本取决于 Ubuntu 22.04 仓库。
- 若 compute 节点 CPU / 内存信息不正确，可手动调整 slurm.conf。
- Playbook 已实现 idempotent（可重复执行而不破坏现有配置）。

---

## 扩展建议

- 可以增加多分区支持，例如 longrun 分区。
- 可集成 LDAP 用户认证。
- 可增加健康检查脚本自动检查节点状态。
- 可通过 Ansible Vault 管理更多敏感信息。

