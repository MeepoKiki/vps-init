# VPS Init - VPS 通用初始化与安全加固脚本

通用 VPS 初始化与安全加固脚本，支持 Fail2ban、防火墙、BBR、SSH 加固、时间同步以及交互式配置。

仓库地址：<https://github.com/MeeopKiki/vps-init>

脚本 Raw 地址：

```text
https://raw.githubusercontent.com/MeeopKiki/vps-init/main/vps-init.sh
```

## 快速使用

脚本包含交互式提问，因此推荐先下载到临时文件，再执行：

```bash
curl -fsSL https://raw.githubusercontent.com/MeeopKiki/vps-init/main/vps-init.sh -o /tmp/vps-init.sh && sudo bash /tmp/vps-init.sh
```

当前已经是 `root` 用户时：

```bash
curl -fsSL https://raw.githubusercontent.com/MeeopKiki/vps-init/main/vps-init.sh -o /tmp/vps-init.sh && bash /tmp/vps-init.sh
```

不建议直接使用 `curl ... | bash`，因为脚本需要读取交互输入。

## 预演

只显示计划执行的命令和配置，不修改系统：

```bash
curl -fsSL https://raw.githubusercontent.com/MeeopKiki/vps-init/main/vps-init.sh -o /tmp/vps-init.sh && sudo bash /tmp/vps-init.sh --dry-run
```

## 交互配置

普通运行时，脚本会依次执行以下交互：

1. 确认自动检测到的 SSH 端口，检测错误时可以输入实际端口。
2. 输入时区，直接按 Enter 使用 `Asia/Shanghai`。
3. 询问是否完整升级所有已安装软件包。
4. 询问是否启用防火墙。
5. 询问是否启用 BBR 和 fq。
6. 询问是否创建 Swap；选择后可自动计算或输入 `512M`、`2G` 等容量。
7. 询问是否安装 Docker Engine 和 Docker Compose。
8. 询问是否启用 SSH 安全加固。
9. 选择 SSH 加固后，询问是否禁用 SSH 密码登录。
10. 显示最终配置并确认是否开始执行。

SSH 端口输入供 Fail2ban 和防火墙使用，不会修改 SSH 服务本身的监听端口。通常直接保留自动检测结果即可。

## 非交互执行

启用防火墙和 BBR：

```bash
curl -fsSL https://raw.githubusercontent.com/MeeopKiki/vps-init/main/vps-init.sh -o /tmp/vps-init.sh && sudo bash /tmp/vps-init.sh --yes --enable-firewall --enable-bbr
```

创建自动容量的 Swap 并安装 Docker：

```bash
curl -fsSL https://raw.githubusercontent.com/MeeopKiki/vps-init/main/vps-init.sh -o /tmp/vps-init.sh && sudo bash /tmp/vps-init.sh --yes --enable-swap --install-docker
```

创建指定容量的 Swap：

```bash
sudo bash /tmp/vps-init.sh --yes --swap-size 2G
```

指定 SSH 端口和时区：

```bash
sudo bash /tmp/vps-init.sh --yes --ssh-port 2222 --timezone Asia/Shanghai --enable-firewall
```

`--yes` 只关闭交互确认，不会自动开启所有可选功能。只有命令中明确指定的功能才会启用。

## 功能

- 自动识别 Debian、Ubuntu、RHEL、Rocky Linux、AlmaLinux、Oracle Linux、Fedora、openSUSE、Arch Linux 和 Alpine Linux 等系统的软件包管理器。
- 支持 `apt`、`dnf`、`yum`、`zypper`、`pacman` 和 `apk`。
- 更新软件包索引并安装 CA 证书、curl、Fail2ban、Chrony 和 QEMU Guest Agent。
- 自动从 `sshd -T` 读取 SSH 实际端口，也可通过参数覆盖检测结果。
- 配置 Fail2ban SSH 防护：10 分钟内失败 5 次封禁 1 小时。
- 重复攻击会递增封禁时间，最长一周。
- 自动选择 systemd journal 或普通日志后端。
- 启动 Fail2ban 前检查配置是否有效。
- 启用 Chrony 时间同步，并支持设置时区。
- 尝试启用 QEMU Guest Agent。
- 系统支持时启用定期 SSD TRIM。
- 可选启用 UFW 或 Firewalld，并先放行当前 SSH 端口。
- 可选启用 BBR 和 fq；内核不支持时自动跳过。
- 可选创建 `/swapfile`。系统已有活动 Swap 时不会重复创建。
- Swap 支持自动计算容量，或者指定 `512M`、`1G`、`2G` 等容量。
- Swap 会写入 `/etc/fstab`，并设置较保守的 `vm.swappiness=10`。
- 可选安装 Docker Engine 和 Docker Compose，并启用 Docker 服务。
- Debian、Ubuntu、RHEL 系、Fedora 使用 Docker 官方安装脚本；openSUSE、Arch Linux 和 Alpine Linux 使用发行版软件包。
- 不会自动把普通用户加入 `docker` 组，因为该组基本等同于 root 权限。
- 可选 SSH 安全加固，包括禁止空密码、限制认证次数、缩短登录等待时间、关闭 X11 转发和 DNS 反查。
- 可选禁用 SSH 密码登录；未检测到 `authorized_keys` 时拒绝执行。
- 修改已有配置前自动备份到 `/root/vps-init-backup-日期时间/`。
- 支持重复执行，不直接覆盖 Fail2ban 和 SSH 的发行版主配置。
- 支持 `--dry-run` 预演。

## 参数

```text
--yes                 非交互执行
--full-upgrade        升级所有已安装软件包
--ssh-port PORT       指定供 Fail2ban 和防火墙使用的 SSH 端口
--timezone ZONE       设置时区
--enable-firewall     启用防火墙
--enable-bbr          启用 BBR + fq
--enable-swap         创建 Swap，已有活动 Swap 时跳过
--swap-size SIZE      设置 Swap 容量，例如 512M、2G 或 auto
--install-docker      安装 Docker Engine 和 Docker Compose
--harden-ssh          添加 SSH 加固配置
--disable-password    禁用 SSH 密码登录，必须配合 --harden-ssh
--dry-run             预演，不修改系统
-h, --help            显示帮助
```

## 执行后检查

检查 Fail2ban、监听端口和失败的 systemd 服务：

```bash
fail2ban-client status sshd
ss -lntp
systemctl --failed
```

检查 Swap：

```bash
swapon --show
free -h
```

检查 Docker：

```bash
docker version
docker compose version
systemctl status docker --no-pager
```

检查 BBR：

```bash
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
```

检查 UFW：

```bash
ufw status verbose
```

检查 Firewalld：

```bash
firewall-cmd --list-all
```

## 注意事项

- 第一次运行时建议保留当前 SSH 会话，同时打开另一个终端验证可以重新登录。
- 启用防火墙前，必须确认脚本识别的 SSH 端口正确。
- 只有验证过 SSH 密钥登录后，才应启用 `--disable-password`。
- 使用 `--full-upgrade` 后，内核或系统组件更新可能需要重启 VPS。
- Docker 发布的容器端口可能绕过 UFW 的普通入站规则。只应使用 `-p` 发布确实需要暴露的端口，并结合云平台安全组限制来源。
- `/swapfile` 默认权限为 `600`，脚本不会覆盖已经存在但无法启用的 `/swapfile`。
- 本脚本不会自动扩容磁盘、删除云厂商 Agent 或修改业务端口。
- Alpine Linux 使用 OpenRC，部分状态检查命令与 systemd 系统不同。

## 更新脚本

每次运行上述 Curl 命令都会重新下载 `main` 分支中的最新版脚本。

如需固定版本，建议在 GitHub 创建版本标签，并使用标签地址：

```text
https://raw.githubusercontent.com/MeeopKiki/vps-init/v1.0.0/vps-init.sh
```
