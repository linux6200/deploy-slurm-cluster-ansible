## **Ubuntu 22.04** 安装、配置步骤

## 🧩 一、系统环境准备

### 1. 更新系统软件源

```bash
sudo apt update && sudo apt upgrade -y
```

### 2. 安装必要依赖

```bash
sudo apt install -y software-properties-common python3 python3-pip python3-venv sshpass
```

---

## 🧭 二、安装 Ansible

### 方法一：通过官方 PPA 安装（推荐）

Ansible 官方为 Ubuntu 提供了稳定 PPA。

```bash
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible
```

### 方法二：通过 pip 安装（可选）

如果希望使用特定版本（如最新开发版），可以用 `pip` 安装：

```bash
python3 -m pip install --upgrade pip
pip install ansible
```

> ✅ **验证安装**

```bash
ansible --version
```

示例输出：

```
ansible [core 2.17.14]
  config file = /etc/ansible/ansible.cfg
  configured module search path = ['/root/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/lib/python3/dist-packages/ansible
  ansible collection location = /root/.ansible/collections:/usr/share/ansible/collections
  executable location = /usr/bin/ansible
  python version = 3.10.12 (main, Aug 15 2025, 14:32:43) [GCC 11.4.0] (/usr/bin/python3)
  jinja version = 3.0.3
  libyaml = True
```

---

## ⚙️ 三、配置 SSH 免密登录（控制节点 → 被控节点）

Ansible 通过 SSH 控制远程主机。推荐使用 **密钥认证方式**。

### 1. 生成 SSH 密钥

```bash
ssh-keygen -t rsa -b 4096
```

一路回车即可。

### 2. 将公钥复制到远程主机

例如控制节点为 `192.168.100.10`，被控节点为 `192.168.100.20`：

```bash
ssh-copy-id user@192.168.100.20
```

如果远程主机暂时不支持密钥，可用密码方式：

```bash
sshpass -p 'remote_password' ssh-copy-id -o StrictHostKeyChecking=no user@192.168.100.20
```

### 3. 验证 SSH 免密是否成功

```bash
ssh user@192.168.100.20 'hostname'
```

能直接登录说明配置成功。

---

## 📁 四、配置 Ansible 清单（Inventory）

编辑主机清单文件（默认 `/etc/ansible/hosts`，或自定义）。

```bash
sudo vim /etc/ansible/hosts
```

添加内容：

```ini
[webservers]
192.168.100.20 ansible_user=user ansible_ssh_private_key_file=~/.ssh/id_rsa

[dbservers]
192.168.100.30 ansible_user=user ansible_ssh_private_key_file=~/.ssh/id_rsa
```

> ✅ 测试连接：

```bash
ansible all -m ping
```

成功输出类似：

```
192.168.100.20 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

---

## 🧰 五、编写并执行第一个 Playbook

### 1. 创建工作目录

```bash
mkdir -p ~/ansible/playbooks
cd ~/ansible/playbooks
```

### 2. 新建 `test.yml` 示例 Playbook

```yaml
---
- name: Test Ansible connectivity
  hosts: all
  become: yes
  tasks:
    - name: Ensure Nginx is installed
      apt:
        name: nginx
        state: present
        update_cache: yes

    - name: Ensure Nginx is running
      service:
        name: nginx
        state: started
        enabled: yes
```

### 3. 执行 Playbook

```bash
ansible-playbook test.yml
```

### 4. 验证执行结果

```bash
ansible all -a "systemctl status nginx"
```

或直接访问远程主机 IP 的 80 端口。

---

## 🧾 六、常用 Ansible 命令速查

| 命令                                                    | 作用                |            |
| ----------------------------------------------------- | ----------------- | ---------- |
| `ansible all -m ping`                                 | 测试所有主机连通性         |            |
| `ansible <group> -m shell -a "uptime"`                | 在指定组执行命令          |            |
| `ansible-playbook xxx.yml`                            | 运行 playbook       |            |
| `ansible-inventory --list`                            | 查看 inventory 结构   |            |
| `ansible-config dump                                  | grep CONFIG_FILE` | 查看当前配置文件路径 |
| `ansible-galaxy collection install community.general` | 安装官方扩展模块          |            |

---

## 🛠 七、可选配置（建议）

### 1. 创建自定义配置文件

```bash
mkdir -p ~/.ansible
vim ~/.ansible.cfg
```

内容示例：

```ini
[defaults]
inventory = ~/ansible/hosts
remote_user = user
host_key_checking = False
retry_files_enabled = False
timeout = 30
interpreter_python = /usr/bin/python3
```

### 2. 设置日志输出（方便调试）

```ini
[defaults]
log_path = ~/ansible/ansible.log
```

---

## 🔍 八、问题排查

| 问题                                          | 解决方法                                                    |
| ------------------------------------------- | ------------------------------------------------------- |
| `FAILED! => "msg": "Missing sudo password"` | 在命令中加 `--ask-become-pass` 或在 playbook 中指定 `become: yes` |
| `Permission denied (publickey)`             | 检查 `ansible_user` 与 `ansible_ssh_private_key_file`      |
| `python3 not found on remote host`          | 在远程主机上执行 `sudo apt install -y python3`                  |
| Inventory 无效                              | 使用 `ansible-inventory -i hosts --list` 检查语法             |

---

## ✅ 九、快速验证环境可用性

运行以下命令确认一切正常：

```bash
ansible all -m ping
ansible all -a "uname -a"
ansible-playbook test.yml
```

如果都成功执行，说明你的 Ansible 环境已正确安装并可使用。

---

