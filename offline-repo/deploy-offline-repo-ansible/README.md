# 功能

✔ 部署离线 APT repo（tar.gz）到所有主机
✔ 自动解压到指定目录（如 /opt/offline-apt-repo）
✔ 禁用系统默认 apt 源（/etc/apt/sources.list & sources.list.d/*）
✔ 仅启用你的离线 repo
✔ 自动执行 apt update 以验证仓库有效

---

# ✅ 目录结构示例

假设你有：

```
ansible/
  ├── inventory.ini
  ├── playbook-offline-apt.yaml
  └── files/
       └── offline-apt-repo.tar.gz   # 离线repo包文件放这里
```

---
# ✅ 使用方式

在 ansible 目录下运行：

```bash
ansible-playbook -i inventory.ini playbook-offline-apt.yaml
```

---

# 🎯 Playbook 功能说明

| 功能            | 说明                                                    |
| ------------- | ----------------------------------------------------- |
| 自动部署离线 repo   | 解压到 /opt/offline-apt-repo                             |
| 禁用默认 apt 源    | 清空 /etc/apt/sources.list + 移走所有 sources.list.d/*.list |
| 启用离线源         | file:{{ offline_repo_root }} ./                       |
| trusted=yes   | 防止因缺少 GPG key 报错                                      |
| 自动 apt update | 确保离线仓库正常工作                                            |

---

# 🔍 验证是否只使用离线源

执行：

```bash
apt-cache policy
```

你应看到只有类似：

```
500 file:/opt/offline-apt-repo ./ Packages
```

---
